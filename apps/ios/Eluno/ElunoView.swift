import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ElunoView: View {
    @ObservedObject var store: ElunoStore
    @State private var scan = false
    @State private var photos = false
    @State private var documents = false
    @State private var compatible = false
    @State private var allowCopies = false
    @State private var remember = false
    @State private var reconnectCode = ""
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var renaming: SharedFile?
    @State private var newCollection = ""
    @State private var exporting: ReceivedFile?
    @State private var deleting: ReceivedFile?
    private let cream = Color(red: 0.96, green: 0.96, blue: 0.93)

    var body: some View {
        NavigationStack {
            content
                .onAppear { store.importShareQueue() }
                .scrollContentBackground(.hidden)
                .background(cream)
                .navigationTitle("eluno.")
                .sheet(isPresented: $scan) { scannerSheet }
                .sheet(isPresented: $photos) {
                    PhotoSelection(compatible: compatible) { providers in
                        photos = false
                        if !providers.isEmpty { store.preparePhotos(providers) }
                    }
                }
                .fileImporter(isPresented: $documents, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): store.stageDocuments(urls)
                    case .failure(let error): store.message = error.localizedDescription
                    }
                }
                .sheet(item: $exporting) { file in
                    ExportFiles(url: file.url) { saved in
                        exporting = nil
                        store.message = saved ? "Copy saved to Files." : "Export cancelled. Your copy is still in Eluno."
                    }
                }
                // A single presented sheet keeps Previous and Next from dismissing the viewer they just opened.
                .sheet(isPresented: Binding(get: { store.viewing != nil }, set: { if !$0 { store.closeViewer() } })) {
                    MediaScreen(store: store)
                }
                .sheet(isPresented: Binding(get: { store.invitation != nil }, set: { if !$0 { store.invitation = nil } })) {
                    connectSheet
                }
                .alert("Collection name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("Collection", text: $newCollection)
                    Button("Save") {
                        if let file = renaming {
                            store.perform { _ = try await store.api?.json("PATCH", "/api/files/\(file.id)", ["collection": newCollection]) }
                        }
                        renaming = nil
                    }
                    Button("Cancel", role: .cancel) { renaming = nil }
                }
                .confirmationDialog("Delete this received copy from Eluno?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete copy", role: .destructive) {
                        if let file = deleting { store.removeReceived(file) }
                        deleting = nil
                    }
                }
        }
    }

    private var content: some View {
        List {
            Section {
                Text("Your world, connected.").font(.title2.weight(.semibold))
                Text(store.message)
            }
            if store.room == nil {
                connectSection
            } else {
                devicesSection
                shareSection
                mediaSection
                if !(store.room?.transfers ?? []).isEmpty {
                    Section("Copies between devices") {
                        ForEach(store.room?.transfers ?? []) { transfer in transferRow(transfer) }
                    }
                }
            }
            receivedSection
            helpSection
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            InvitationScanner(scanned: { value in
                scan = false
                store.scanned(value)
            }, failed: { reason in
                scan = false
                store.message = reason
            })
            .navigationTitle("Scan invitation")
            .toolbar { Button("Cancel") { scan = false } }
        }
    }

    private var connectSheet: some View {
        NavigationStack {
            Form {
                Text("Connect to the computer whose invitation you scanned. It will ask you to approve this device.")
                Toggle("Remember this computer’s identity", isOn: $remember)
                Button("Connect") {
                    if let invite = store.invitation { store.connect(invite, remember: remember) }
                }
                Button("Cancel", role: .cancel) { store.invitation = nil }
            }
            .navigationTitle("Connect your screens")
        }
        .presentationDetents([.medium, .large])
    }

    private var connectSection: some View {
        Section("Connect your screens") {
            TextField("This device’s name", text: $store.name).textContentType(.nickname)
            Button("Scan computer invitation") { scan = true }
            Text("Use the same Wi-Fi. The camera reads the invitation; your computer approves the connection.").font(.footnote)
            if store.connecting { ProgressView("Connecting securely…") }
            if store.pending || store.connecting {
                Button("Cancel request", role: .cancel) { store.disconnect() }
            }
            if store.remembered != nil {
                TextField("Current six-digit code", text: $reconnectCode).keyboardType(.numberPad)
                Button("Reconnect to remembered computer") { store.reconnect(code: reconnectCode) }
                Button("Forget computer", role: .destructive) { store.forget() }
                Text("Reconnection verifies the saved identity and still asks for computer approval. Scan again if its network address changed.").font(.footnote)
            }
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Camera or Local Network off? Open Settings", destination: settings)
            }
        }
    }

    private var devicesSection: some View {
        Section("Your devices") {
            ForEach(store.room?.members ?? []) { device in
                Label(deviceLabel(device), systemImage: device.id == store.deviceID ? "iphone" : "display")
            }
            Button("Disconnect", role: .destructive) { store.disconnect() }
        }
    }

    private func deviceLabel(_ device: Device) -> String {
        var label = device.name
        if device.id == store.deviceID { label += " (this device)" }
        if device.online == false { label += " · offline" }
        return label
    }

    private var shareSection: some View {
        Section("Share something") {
            Toggle("Prepare a compatible Photos version", isOn: $compatible)
            Text(compatible ? "Apple prepares a compatible representation when available. Your original is unchanged. Eluno shows the format it actually received." : "Original HEIC/HEVC media may not play on every device. Turn on compatibility before selecting to request conversion.").font(.footnote)
            Button("Choose photos or videos") { photos = true }.disabled(store.preparing)
            Button("Choose from Files") { documents = true }.disabled(store.preparing)
            if store.preparing {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    ProgressView("Preparing selected files, including iCloud downloads…", value: store.photoPreparationFraction)
                }
                Button("Cancel preparation") { store.cancelPreparation() }
            }
            if !store.prepared.isEmpty {
                ForEach(store.prepared) { file in preparedRow(file) }
                TextField("Collection / album name", text: $store.collectionName)
                Toggle("Allow saving copies", isOn: $allowCopies)
                Button("Share selected items to view") {
                    store.perform { try await store.sharePrepared(copies: allowCopies) }
                }
                .disabled(store.preparing || store.sharing)
                Button("Discard selection", role: .destructive) { store.discardPrepared() }.disabled(store.sharing)
            }
        }
    }

    private func preparedRow(_ file: PreparedFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(file.name) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
            if let format = file.format {
                Text(format.interoperable ? format.summary : "\(format.summary). May not play on every device. Choose a compatible Photos version, or send the original as a copy.").font(.caption)
            }
        }
    }

    private var mediaSection: some View {
        Section("Shared media") {
            TextField("Find files, collections or a device", text: $search)
            Toggle("Favorites in this connection", isOn: $favoritesOnly)
            ForEach(filteredFiles) { file in fileRow(file) }
            if filteredFiles.isEmpty { Text("Shared items will appear here. Try another search or add media from a connected device.") }
        }
    }

    private func fileRow(_ file: SharedFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(file.name).font(.headline)
            if let collection = file.collection, !collection.isEmpty { Text(collection).font(.subheadline) }
            Text("\(owner(file)) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))").font(.caption)
            // Stacks the actions when larger text or a narrow iPad window leaves no room in one line.
            ViewThatFits(in: .horizontal) {
                HStack { fileActions(file) }
                VStack(alignment: .leading) { fileActions(file) }
            }
            Button(store.favorites.contains(file.id) ? "Unfavorite" : "Favorite") { store.toggleFavorite(file) }
            if file.allowDownload && store.supportsSaveCopy {
                Button("Save copy to Eluno inbox") { store.saveCopy(file) }.disabled(store.downloading)
            }
            if file.ownerId != store.deviceID && !file.allowDownload && store.supportsCopies {
                Text("To receive a permanent copy, ask \(owner(file)) to choose Send a copy → \(store.name).").font(.caption)
            }
        }
        .padding(.vertical, 8)
        // In a List, automatic-style buttons in one row all fire together when the row is tapped.
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func fileActions(_ file: SharedFile) -> some View {
        if ImportRules.isStreamable(file.type) {
            Button(file.type.hasPrefix("video/") ? "Play" : "View") { store.open(file) }
        }
        if file.ownerId == store.deviceID {
            if store.supportsCopies {
                Menu("Send a copy") {
                    let receivers = (store.room?.members ?? []).filter { $0.id != store.deviceID && $0.online != false }
                    if receivers.isEmpty { Text("Connect another device first") }
                    ForEach(receivers) { device in
                        Button(device.name) { store.perform { try await store.offer(file, to: device) } }
                    }
                }
            }
            Menu("Access") {
                Button("Move to collection") {
                    newCollection = file.collection ?? ""
                    renaming = file
                }
                Button(file.allowDownload ? "Disable copies" : "Allow copies") {
                    store.perform { _ = try await store.api?.json("PATCH", "/api/files/\(file.id)", ["allowDownload": !file.allowDownload]) }
                }
                Button("Stop sharing", role: .destructive) { store.perform { try await store.stopSharing(file) } }
            }
        }
    }

    private var receivedSection: some View {
        Section("Received copies · available offline") {
            if store.downloading {
                ProgressView("Saving a copy…", value: store.downloadProgress)
                Button("Cancel download") { store.cancelDownload() }
            }
            if store.received.isEmpty { Text("Copies you accept into Eluno appear here. They remain after disconnecting.") }
            ForEach(store.received) { file in receivedRow(file) }
        }
    }

    private func receivedRow(_ file: ReceivedFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.name).font(.headline)
            photosStatus(file)
            ViewThatFits(in: .horizontal) {
                HStack { receivedActions(file) }
                VStack(alignment: .leading) { receivedActions(file) }
            }
            Button("Delete from Eluno", role: .destructive) { deleting = file }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func photosStatus(_ file: ReceivedFile) -> some View {
        switch file.photos {
        case .notRequested: EmptyView()
        case .inProgress: Text("Adding to Photos…").font(.caption)
        case .saved: Text("Also saved in Photos.").font(.caption)
        case .failed(let reason): Text(reason).font(.caption)
        }
    }

    @ViewBuilder private func receivedActions(_ file: ReceivedFile) -> some View {
        Button("Save to Files") { exporting = file }
        if ImportRules.isPhotosCompatible(file.type) {
            Button(file.photos == .saved ? "Save to Photos again" : "Save to Photos") { store.saveToPhotos(file) }
                .disabled(file.photos == .inProgress)
        }
    }

    private var helpSection: some View {
        Section("A little help") {
            Text("Keep Eluno open on both devices. Transfers pause in the background; tap Resume when you return. Resume requires the same connection and source item. A new session requires a new offer.")
            Text("Use a private home network, not guest Wi-Fi. If a network change prevents reconnection, scan a fresh invitation. You can forget a remembered computer at any time.")
            if let releases = URL(string: "https://github.com/beingaeditor/Eluno/releases") {
                Link("Release downloads and updates", destination: releases)
            }
        }
    }

    private func owner(_ file: SharedFile) -> String { memberName(file.ownerId) ?? "Sharing device" }

    private func memberName(_ id: String) -> String? { store.room?.members.first(where: { $0.id == id })?.name }

    private var filteredFiles: [SharedFile] {
        let files = store.room?.files ?? []
        return files.filter { file in
            if favoritesOnly && !store.favorites.contains(file.id) { return false }
            if search.isEmpty { return true }
            let searchable: String = [file.name, file.collection ?? "", owner(file)].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(search)
        }
    }

    private func transferSummary(_ t: CopyTransfer) -> String {
        let receiving = t.receiverId == store.deviceID
        let peer = memberName(receiving ? t.senderId : t.receiverId) ?? "Disconnected device"
        let direction = receiving ? "From \(peer)" : "To \(peer)"
        let done = ByteCountFormatter.string(fromByteCount: t.bytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: t.size, countStyle: .file)
        return "\(direction) · \(t.status) · \(done) of \(total)"
    }

    private func transferRow(_ t: CopyTransfer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t.name).font(.headline)
            Text(transferSummary(t)).font(.caption)
            ProgressView(value: Double(t.bytes), total: Double(t.size)).accessibilityLabel(t.name + " transfer progress")
            if let error = store.transferErrors[t.id] {
                Text(error).font(.footnote)
            } else if !t.error.isEmpty {
                Text(t.error).font(.footnote)
            }
            if !t.ended {
                if t.receiverId == store.deviceID {
                    if store.busyTransfers.contains(t.id) {
                        Button("Pause") { store.pause(t) }
                    } else {
                        Button(t.status == "offered" ? "Accept into Eluno inbox" : "Resume into Eluno inbox") { store.receive(t) }
                        if t.status == "offered" && ImportRules.isPhotosCompatible(t.type) {
                            Button("Accept and add to Photos") { store.receive(t, photos: true) }
                        }
                    }
                    if t.status == "offered" {
                        Button("Decline") { store.perform { try await store.transferAction(t, "decline") } }
                    }
                }
                Button("Cancel transfer", role: .destructive) {
                    store.perform {
                        try await store.transferAction(t, "cancel")
                        store.pause(t)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        // In a List, automatic-style buttons in one row all fire together: Accept would also Decline and Cancel.
        .buttonStyle(.bordered)
    }
}

private struct MediaScreen: View {
    @ObservedObject var store: ElunoStore
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let file = store.viewing { viewer(file) } else { Color.clear }
            }
            .navigationTitle(store.viewing?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { store.closeViewer() } }
        }
    }

    @ViewBuilder private func viewer(_ file: SharedFile) -> some View {
        VStack {
            if let player = store.player {
                VideoPlayer(player: player)
                if let error = store.viewerError {
                    unavailable(file, reason: error)
                } else {
                    Text("If this video can’t play, ask the sender for a compatible version. HEVC and WebM support depends on the device.").font(.footnote).padding()
                }
            } else if let photo = store.photo {
                photoView(photo, file: file)
                ViewThatFits(in: .horizontal) {
                    HStack { photoControls }
                    VStack { photoControls }
                }
                .buttonStyle(.bordered)
                .padding()
            } else if let error = store.viewerError {
                unavailable(file, reason: error)
            } else {
                ProgressView("Opening media…")
            }
        }
    }

    private func unavailable(_ file: SharedFile, reason: String) -> some View {
        VStack(spacing: 12) {
            Text(reason).font(.footnote)
            if file.allowDownload && store.supportsSaveCopy {
                Button("Save a copy instead") {
                    store.saveCopy(file)
                    store.closeViewer()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func photoView(_ photo: UIImage, file: SharedFile) -> some View {
        // Sizing the image itself, rather than scaling it, lets the scroll view reach all of a zoomed photo.
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * zoom, height: proxy.size.height * zoom)
                    .accessibilityLabel(file.name)
            }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in zoom = min(4, max(1, pinchStart * value)) }
                .onEnded { _ in pinchStart = zoom }
        )
    }

    @ViewBuilder private var photoControls: some View {
        Button("Previous") { move(-1) }
        Button(zoom > 1 ? "Fit photo" : "Zoom photo") {
            zoom = zoom > 1 ? 1 : 2
            pinchStart = zoom
        }
        Button("Next") { move(1) }
    }

    private func move(_ delta: Int) {
        let photos = (store.room?.files ?? []).filter { $0.type.hasPrefix("image/") && ImportRules.isStreamable($0.type) }
        guard !photos.isEmpty, let current = store.viewing, let index = photos.firstIndex(where: { $0.id == current.id }) else { return }
        zoom = 1
        pinchStart = 1
        store.open(photos[(index + delta + photos.count) % photos.count])
    }
}
