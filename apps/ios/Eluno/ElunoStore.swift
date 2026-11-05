import SwiftUI
import AVFoundation
import Photos
import UniformTypeIdentifiers
import ImageIO
import CoreMedia

struct PreparedFile: Identifiable {
    let id = UUID(); let url: URL; let name: String; let type: String; let size: Int64
    var format: MediaFormat? = nil
}
struct ReceivedFile: Identifiable {
    var id: URL { url }
    let url: URL
    var photos: PhotosOutcome = .notRequested
    var name: String { url.lastPathComponent }
    var type: String { ElunoStore.mimeType(forName: url.lastPathComponent) }
}

/// Outside the main-actor store so nonisolated helpers can read them.
private enum StoragePaths {
    static let appGroup = "group.app.eluno.shared"
    static let partial = ".eluno.part"
    static let photosMarker = ".eluno.photos"
    static let pendingSharePrefix = ".pending-"
}

@MainActor final class ElunoStore: ObservableObject {
    @Published var name = UserDefaults.standard.string(forKey: "deviceName") ?? "My iPhone or iPad"
    @Published var message = "Open Eluno on your computer and scan its invitation."
    @Published var room: Room?
    @Published var pending = false
    @Published var connecting = false
    @Published var invitation: Invitation?
    @Published var prepared: [PreparedFile] = []
    @Published var preparing = false
    @Published var preparation: Double = 0
    @Published var sharing = false
    @Published var received: [ReceivedFile] = []
    @Published var player: AVPlayer?
    @Published var photo: UIImage?
    @Published var viewing: SharedFile?
    @Published var viewerError: String?
    @Published var transferErrors: [String: String] = [:]
    @Published var busyTransfers = Set<String>()
    @Published var remembered: Invitation?
    @Published var favorites = Set<String>()
    @Published var collectionName = ""
    @Published var downloading = false
    @Published var downloadProgress: Double = 0
    /// What the connected computer reported in `/api/health`. Copy actions stay hidden without it.
    @Published var health: CoordinatorHealth?
    var api: PinnedAPI?

    private var connection: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var serving: [String: Task<Void, Never>] = [:]
    private var transferring: [String: Task<Void, Never>] = [:]
    private var sources: [String: PreparedFile] = [:]
    private var incoming: [String: IncomingJob] = [:]
    private var loader: PinnedPlayer?
    private var playerObservation: NSKeyValueObservation?
    private var positions: [String: Double] = [:]
    private var viewTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var providerProgress: [Progress] = []
    private var importToken = ImportToken()
    private var remainingProviders = 0
    private var totalProviders = 0
    private var preparationFailures: [String] = []
    private var generation = UUID()
    private var pendingSince = Date()
    private var identityToRemember: Invitation?
    private var downloadTask: Task<Void, Never>?
    private var active = true
    private var photosInFlight = Set<URL>()
    private var photosFailures: [URL: String] = [:]
    private let fm = FileManager.default
    private var inbox: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Received", isDirectory: true) }
    var deviceID: String { api?.deviceID ?? "" }
    var supportsCopies: Bool { health?.supportsCopies == true }
    var supportsSaveCopy: Bool { health?.supportsSaveCopy == true }

    init() {
        if let data = UserDefaults.standard.data(forKey: "computerIdentity") { remembered = try? JSONDecoder().decode(Invitation.self, from: data) }
        removeAbandonedInboxFolders()
        refreshReceived()
        // Only this app's temporary imports are removed. Received copies persist.
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("ElunoImports", isDirectory: true))
    }

    func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() } catch { message = error.localizedDescription }
        }
    }

    func toggleFavorite(_ file: SharedFile) {
        if favorites.contains(file.id) {
            favorites.remove(file.id)
        } else {
            favorites.insert(file.id)
        }
    }

    // MARK: - Pairing

    func scanned(_ text: String) {
        do {
            invitation = try Invitation.parse(text)
        } catch {
            invitation = nil
            message = error.localizedDescription
        }
    }

    func connect(_ invite: Invitation, remember: Bool) {
        let deviceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceName.isEmpty, deviceName.utf16.count <= Wire.maxNameUnits else {
            message = "Enter a device name up to 120 characters."
            return
        }
        invitation = nil
        guard !invite.isExpired() else {
            message = Invitation.expiredMessage
            return
        }
        let selection = prepared
        prepared = []
        disconnect()
        prepared = selection
        let current = generation
        connecting = true
        message = "Connecting securely…"
        UserDefaults.standard.set(deviceName, forKey: "deviceName")
        if remember {
            identityToRemember = Invitation(v: Wire.protocolVersion, endpoints: invite.endpoints, fingerprint: invite.fingerprint, code: "", expiresAt: 0)
        }
        connection = Task {
            await attemptConnection(invite, deviceName: deviceName, generation: current)
        }
    }

    /// Tries each address until one answers. Every await is followed by a generation check, so a
    /// cancelled or superseded attempt can never attach this app to the session it reached.
    private func attemptConnection(_ invite: Invitation, deviceName: String, generation current: UUID) async {
        // The system can refuse local connections while its permission alert is still on screen,
        // so unanswered addresses get a few spaced retries within an overall limit.
        let deadline = Date().addingTimeInterval(45)
        var failures: [Error] = []
        for delay: UInt64 in [0, 2, 4] {
            if delay > 0 {
                // Retrying can't change a certificate that doesn't match.
                guard failures.contains(where: { ($0 as? ElunoError)?.kind != .identityChanged }) else { break }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
            for endpoint in invite.endpoints {
                guard generation == current, !Task.isCancelled else { return }
                guard Date() < deadline else { break }
                guard let client = try? PinnedAPI(endpoint: endpoint, fingerprint: invite.fingerprint) else { continue }
                do {
                    let report = try await client.json("GET", "/api/health", timeout: 6)
                    let coordinator = try CoordinatorHealth(report)
                    guard generation == current else { client.close(); return }
                    let device = try await client.json("POST", "/api/devices", ["name": deviceName])
                    guard let token = device["token"] as? String, let id = device["id"] as? String else { throw ElunoError("Invalid registration response.") }
                    client.token = token
                    client.deviceID = id
                    guard generation == current else { client.close(); return }
                    _ = try await client.json("POST", "/api/join", ["code": invite.code])
                    guard generation == current else {
                        _ = try? await client.json("POST", "/api/leave")
                        client.close()
                        return
                    }
                    api = client
                    health = coordinator
                    pending = true
                    connecting = false
                    pendingSince = Date()
                    message = "Approve this device on your computer."
                    startPoll(client)
                    return
                } catch {
                    client.close()
                    guard generation == current, !Task.isCancelled else { return }
                    if PairingFailure.isFinal(error) {
                        failConnection(PairingFailure.message(forFinal: error))
                        return
                    }
                    failures.append(error)
                }
            }
        }
        if generation == current { failConnection(PairingFailure.summary(failures)) }
    }

    private func failConnection(_ text: String) {
        connecting = false
        identityToRemember = nil
        message = text
    }

    func reconnect(code: String) {
        guard let saved = remembered, code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
            message = "Enter the current six-digit code shown on your computer."
            return
        }
        connect(Invitation(v: Wire.protocolVersion, endpoints: saved.endpoints, fingerprint: saved.fingerprint, code: code, expiresAt: Date().timeIntervalSince1970 * 1000 + 60000), remember: false)
    }

    func forget() {
        remembered = nil
        UserDefaults.standard.removeObject(forKey: "computerIdentity")
    }

    private func startPoll(_ client: PinnedAPI) {
        polling?.cancel()
        polling = Task {
            var version = -1
            var interrupted = false
            while !Task.isCancelled && api === client {
                do {
                    if !active {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    let data = try await client.data("/api/events?since=\(version)")
                    let next = try JSONDecoder().decode(Snapshot.self, from: data)
                    guard api === client, !Task.isCancelled else { return }
                    version = next.version
                    if interrupted {
                        interrupted = false
                        if next.room != nil { message = "Connection restored. Keep Eluno open while sharing or receiving." }
                    }
                    apply(next, client: client)
                } catch {
                    guard !Task.isCancelled, api === client else { return }
                    if PairingFailure.endsSession(error) {
                        endSession("Your computer restarted or no longer recognizes this device. Scan a fresh invitation. Received copies remain in your inbox.")
                        return
                    }
                    if pending, Date().timeIntervalSince(pendingSince) > 75 {
                        endSession("Your computer stopped responding before approving this device. Scan a fresh invitation to try again.", keepSelection: true)
                        return
                    }
                    interrupted = true
                    message = "Connection interrupted. Eluno will retry while open."
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }
        }
    }

    private func apply(_ next: Snapshot, client: PinnedAPI) {
        let previous = room
        if next.room == nil, !next.pending {
            if previous != nil {
                endSession("Connection ended. Received copies remain in your inbox.")
                return
            }
            if pending {
                // The coordinator reports a refusal and an expired request the same way. It drops
                // unanswered requests after 60 seconds, so elapsed time tells them apart.
                let timedOut = Date().timeIntervalSince(pendingSince) >= 55
                endSession(timedOut
                    ? "Approval timed out. Scan a fresh invitation, then approve this device on your computer within a minute."
                    : "Your computer declined this device. To try again, scan a fresh invitation and approve it there.", keepSelection: true)
                return
            }
        }
        room = next.room
        pending = next.pending
        if previous == nil, next.room != nil {
            // Remembered only now, so a declined or abandoned attempt leaves no saved identity.
            if let identity = identityToRemember, let data = try? JSONEncoder().encode(identity) {
                remembered = identity
                UserDefaults.standard.set(data, forKey: "computerIdentity")
            }
            identityToRemember = nil
            message = supportsCopies
                ? "Connected. Keep Eluno open while sharing or receiving."
                : "Connected. Sending copies needs Eluno 0.3.0 on your computer. Viewing still works."
        }
        if let current = viewing, next.room?.files.contains(where: { $0.id == current.id }) != true {
            closeViewer()
            message = "The sharing device stopped sharing that item."
        }
        for read in next.reads where serving[read.id] == nil {
            serving[read.id] = Task {
                defer { serving.removeValue(forKey: read.id) }
                do {
                    try await serve(read, client: client)
                } catch {
                    if !Task.isCancelled { message = "Source unavailable. Select the item again if it moved." }
                }
            }
        }
        reconcileIncoming(next.room?.transfers ?? [])
    }

    // MARK: - Serving your files

    private func serve(_ read: ReadRequest, client: PinnedAPI) async throws {
        let route = "/api/chunks/\(read.id)"
        guard let source = sources[read.fileId], read.start >= 0, read.end >= read.start, read.end - read.start < Wire.chunkBytes, read.end < source.size else {
            // A wrong-length reply makes the coordinator fail this read now, instead of the viewer waiting out its timeout.
            _ = try? await client.data(route, method: "POST", body: Data())
            return
        }
        let url = source.url, start = read.start, count = Int(read.end - read.start + 1)
        let bytes: Data
        do {
            bytes = try await Task.detached(priority: .userInitiated) { try Self.readChunk(url, start: start, count: count) }.value
        } catch {
            _ = try? await client.data(route, method: "POST", body: Data())
            throw error
        }
        do {
            _ = try await client.data(route, method: "POST", body: bytes)
        } catch let refused as ElunoError where refused.status == 410 {
            // The viewer cancelled, or a late snapshot repeated a read that was already answered.
        }
    }

    nonisolated private static func readChunk(_ url: URL, start: Int64, count: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(start))
        let bytes = try file.read(upToCount: count) ?? Data()
        guard bytes.count == count else { throw ElunoError("Source changed. Select it again.") }
        return bytes
    }

    // MARK: - Preparing a selection

    /// Starts an import owned by a new token. Callbacks from any earlier import see their token no longer
    /// matches, remove only their own temporary files, and change nothing else.
    private func beginImport(total: Int) -> ImportToken {
        cancelPreparation()
        preparing = true
        preparation = 0
        totalProviders = total
        remainingProviders = total
        preparationFailures = []
        return importToken
    }

    func stageDocuments(_ urls: [URL]) {
        let selected = Array(urls.prefix(Wire.maxFilesPerRequest))
        let omitted = urls.count - selected.count
        let token = beginImport(total: selected.count)
        preparationTask = Task {
            for (index, url) in selected.enumerated() {
                guard token === importToken else { return }
                let coordinator = NSFileCoordinator()
                let worker = Task.detached { () throws -> PreparedFile in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try Self.stage(url, coordinator: coordinator, isCancelled: { token.isCancelled })
                }
                do {
                    let staged = try await withTaskCancellationHandler(operation: {
                        try await worker.value
                    }, onCancel: {
                        worker.cancel()
                        coordinator.cancel()
                    })
                    let ready = await Self.inspected(staged)
                    guard token === importToken else {
                        Self.removeStaged(ready)
                        return
                    }
                    prepared.append(ready)
                } catch {
                    guard token === importToken else { return }
                    if !Self.isCancellation(error) { preparationFailures.append(error.localizedDescription) }
                }
                preparation = Double(index + 1) / Double(max(selected.count, 1))
            }
            guard token === importToken else { return }
            finishImport(omitted: omitted)
        }
    }

    func preparePhotos(_ providers: [NSItemProvider]) {
        let token = beginImport(total: providers.count)
        for provider in providers {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.image.identifier
            let suggested = provider.suggestedName
            let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                // The provider deletes this temporary file when the callback returns, so copy it here.
                var staged: PreparedFile?
                var failure: Error? = error
                if let url, !token.isCancelled {
                    do {
                        staged = try Self.stage(url, suggestedName: suggested, isCancelled: { token.isCancelled })
                    } catch {
                        failure = error
                    }
                }
                let result = staged, issue = failure
                Task { @MainActor in
                    await self.finishProvider(result, issue: issue, token: token)
                }
            }
            providerProgress.append(progress)
        }
    }

    private func finishProvider(_ file: PreparedFile?, issue: Error?, token: ImportToken) async {
        guard token === importToken else {
            Self.removeStaged(file)
            return
        }
        var ready = file
        if let file { ready = await Self.inspected(file) }
        guard token === importToken else {
            Self.removeStaged(ready)
            return
        }
        if let ready { prepared.append(ready) }
        if let issue, !Self.isCancellation(issue) { preparationFailures.append(issue.localizedDescription) }
        remainingProviders -= 1
        if remainingProviders <= 0 { finishImport(omitted: 0) }
    }

    private func finishImport(omitted: Int) {
        preparing = false
        providerProgress.removeAll()
        var notes: [String] = []
        if let last = preparationFailures.last {
            notes.append("\(preparationFailures.count) of \(totalProviders) items could not be prepared. \(last)")
        }
        if omitted > 0 { notes.append("Eluno prepares up to \(Wire.maxFilesPerRequest) items at a time, so \(omitted) were left out.") }
        if !notes.isEmpty { message = notes.joined(separator: " ") }
    }

    func cancelPreparation() {
        importToken.cancel()
        importToken = ImportToken()
        preparationTask?.cancel()
        providerProgress.forEach { $0.cancel() }
        providerProgress.removeAll()
        preparing = false
    }

    nonisolated static func stage(_ source: URL, suggestedName: String? = nil, coordinator: NSFileCoordinator = NSFileCoordinator(), isCancelled: @escaping () -> Bool) throws -> PreparedFile {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("ElunoImports/\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = source.lastPathComponent
        if let suggestedName, !suggestedName.isEmpty, !source.pathExtension.isEmpty { name = suggestedName + "." + source.pathExtension }
        name = FileNames.inboxName(name)
        let type = mimeType(forName: name)
        let target = directory.appendingPathComponent(name)
        var coordinationError: NSError?
        var stagingError: Error?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { resolved in
            do {
                // Refuse an oversized photo before spending time and space copying it.
                if let known = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize, known > 0 {
                    try ImportRules.validate(name: name, type: type, size: Int64(known))
                }
                fm.createFile(atPath: target.path, contents: nil)
                let input = try FileHandle(forReadingFrom: resolved)
                let output = try FileHandle(forWritingTo: target)
                defer {
                    try? input.close()
                    try? output.close()
                }
                var finished = false
                while !finished {
                    // Without a pool per chunk, read buffers pile up until a large copy finishes.
                    try autoreleasepool {
                        if isCancelled() { throw CancellationError() }
                        if let bytes = try input.read(upToCount: Int(Wire.chunkBytes)), !bytes.isEmpty {
                            try output.write(contentsOf: bytes)
                        } else {
                            finished = true
                        }
                    }
                }
            } catch {
                stagingError = error
            }
        }
        do {
            if let stagingError { throw stagingError }
            if let coordinationError { throw coordinationError }
            let size = (try fm.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            try ImportRules.validate(name: name, type: type, size: size)
            return PreparedFile(url: target, name: name, type: type, size: size)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    nonisolated static func mimeType(forName name: String) -> String {
        let pathExtension = NSString(string: name).pathExtension
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Adds what the file really contains, so the app never claims compatibility it hasn't checked.
    nonisolated private static func inspected(_ file: PreparedFile) async -> PreparedFile {
        var result = file
        guard file.type.hasPrefix("video/") else {
            result.format = MediaFormat.image(mime: file.type)
            return result
        }
        let asset = AVURLAsset(url: file.url)
        let videoCodecs = await codecs(of: asset, mediaType: .video)
        let audioCodecs = await codecs(of: asset, mediaType: .audio)
        result.format = MediaFormat.video(mime: file.type, videoCodecs: videoCodecs, audioCodecs: audioCodecs)
        return result
    }

    nonisolated private static func codecs(of asset: AVURLAsset, mediaType: AVMediaType) async -> [String] {
        guard let tracks = try? await asset.loadTracks(withMediaType: mediaType) else { return [] }
        var names: [String] = []
        for track in tracks {
            guard let descriptions = try? await track.load(.formatDescriptions) else { continue }
            for description in descriptions {
                let code: UInt32 = CMFormatDescriptionGetMediaSubType(description)
                var text = ""
                for shift: UInt32 in [24, 16, 8, 0] {
                    if let scalar = Unicode.Scalar((code >> shift) & 0xFF) { text.unicodeScalars.append(scalar) }
                }
                names.append(text)
            }
        }
        return names
    }

    nonisolated private static func removeStaged(_ file: PreparedFile?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        return (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError) || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }

    var photoPreparationFraction: Double {
        guard !providerProgress.isEmpty else { return preparation }
        return providerProgress.map(\.fractionCompleted).reduce(0, +) / Double(providerProgress.count)
    }

    func discardPrepared() {
        for file in prepared { try? fm.removeItem(at: file.url.deletingLastPathComponent()) }
        prepared.removeAll()
    }

    func sharePrepared(copies: Bool) async throws {
        guard let client = api, room != nil else { throw ElunoError("Connect first.") }
        guard !sharing else { return }
        sharing = true
        defer { sharing = false }
        let files = Array(prepared.prefix(Wire.maxFilesPerRequest))
        let offered = files.map { file -> [String: Any] in
            ["name": file.name, "type": file.type, "size": file.size, "allowDownload": copies, "collection": collectionName]
        }
        let result = try await client.json("POST", "/api/files", ["files": offered])
        guard api === client, let added = result["files"] as? [[String: Any]], added.count == files.count else { throw ElunoError("Connection changed. Select your files again.") }
        for (item, file) in zip(added, files) {
            if let id = item["id"] as? String { sources[id] = file }
        }
        let shared = Set(files.map(\.id))
        prepared.removeAll { shared.contains($0.id) }
    }

    func stopSharing(_ file: SharedFile) async throws {
        _ = try await api?.json("DELETE", "/api/files/\(file.id)")
        if let local = sources.removeValue(forKey: file.id) { try? fm.removeItem(at: local.url.deletingLastPathComponent()) }
    }

    // MARK: - Sending and receiving copies

    func offer(_ file: SharedFile, to device: Device) async throws {
        guard supportsCopies else { throw ElunoError("Sending copies needs Eluno 0.3.0 on your computer.") }
        _ = try await api?.json("POST", "/api/transfers", ["fileId": file.id, "receiverId": device.id])
        message = "Offer sent to \(device.name). They choose whether to accept it."
    }

    func transferAction(_ t: CopyTransfer, _ action: String) async throws {
        _ = try await api?.json("PATCH", "/api/transfers/\(t.id)", ["action": action])
    }

    func pause(_ t: CopyTransfer) { transferring[t.id]?.cancel() }

    func receive(_ t: CopyTransfer, photos: Bool = false) {
        guard supportsCopies, !busyTransfers.contains(t.id), let client = api else { return }
        busyTransfers.insert(t.id)
        transferErrors[t.id] = nil
        transferring[t.id] = Task {
            defer {
                transferring[t.id] = nil
                busyTransfers.remove(t.id)
            }
            do {
                try await runReceive(t, photos: photos, client: client)
            } catch {
                await receiveFailed(t.id, error: error, client: client)
            }
        }
    }

    private func runReceive(_ t: CopyTransfer, photos: Bool, client: PinnedAPI) async throws {
        // A row can outlive the transfer by one snapshot. Reconciliation settles anything already ended.
        if let current = latestStatus(of: t.id), TransferStatus.isEnded(current) { return }
        try await prepareJob(for: t, photos: photos)
        guard var job = incoming[t.id] else { return }
        let status = latestStatus(of: t.id) ?? t.status
        // A previous attempt may have published the copy and lost only the coordinator's reply.
        if !job.published {
            job.bytes = try Self.verifiedOffset(partial: job.partial, claimed: job.bytes)
            incoming[t.id] = job
        }
        let route = try await openTransfer(t.id, status: status, offset: job.published ? job.size : job.bytes, client: client)
        if !job.published {
            do {
                let output = try FileHandle(forWritingTo: job.partial)
                defer { try? output.close() }
                try output.seek(toOffset: UInt64(job.bytes))
                while job.bytes < job.size {
                    try Task.checkCancellation()
                    let end = min(job.bytes + Wire.chunkBytes, job.size) - 1
                    let bytes = try await client.data(route, range: job.bytes...end, total: job.size)
                    try Task.checkCancellation()
                    try output.write(contentsOf: bytes)
                    job.bytes += Int64(bytes.count)
                    incoming[t.id] = job
                    _ = try await client.json("PATCH", "/api/transfers/\(t.id)", ["action": "progress", "bytes": job.bytes])
                }
                try output.synchronize()
            }
            try Task.checkCancellation()
            try publish(t.id)
        }
        try await acknowledge(t.id, client: client)
    }

    /// Runs the checks that belong before acceptance, then creates the private incomplete file once.
    private func prepareJob(for t: CopyTransfer, photos: Bool) async throws {
        if let job = incoming[t.id] {
            let remaining = job.published ? 0 : job.size - job.bytes
            if remaining > 0 { try requireSpace(for: remaining) }
            return
        }
        if photos {
            guard ImportRules.isPhotosCompatible(t.type) else { throw ElunoError("Use the Eluno inbox for this file.") }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else { throw ElunoError("Photos access was not granted. Accept into the Eluno inbox instead, or allow Photos in Settings.") }
        }
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        try requireSpace(for: t.size)
        // A unique private directory prevents overwriting any received copy with the same name.
        let directory = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(StoragePaths.partial)
        fm.createFile(atPath: partial.path, contents: nil)
        incoming[t.id] = IncomingJob(directory: directory, partial: partial, finalURL: directory.appendingPathComponent(FileNames.inboxName(t.name)), type: t.type, size: t.size, wantsPhotos: photos)
    }

    private func requireSpace(for bytes: Int64) throws {
        let space = try inbox.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard space > bytes + 1_048_576 else { throw ElunoError("Not enough device storage. Free some space and try again.") }
    }

    /// Resume only from bytes that are really on disk, and drop anything past the last recorded chunk.
    nonisolated private static func verifiedOffset(partial: URL, claimed: Int64) throws -> Int64 {
        let actual = (try FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0
        let verified = min(claimed, actual)
        if actual != verified {
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }
            try output.truncate(atOffset: UInt64(verified))
        }
        return verified
    }

    private func latestStatus(of id: String) -> String? { room?.transfers?.first(where: { $0.id == id })?.status }

    private func openTransfer(_ id: String, status: String, offset: Int64, client: PinnedAPI) async throws -> String {
        let route = "/api/transfers/\(id)"
        let action = status == "offered" ? "accept" : "resume"
        // A missed pause acknowledgement can leave the coordinator still receiving.
        if status == "receiving" { _ = try? await client.json("PATCH", route, ["action": "pause"]) }
        do {
            return try await requestAccess(route, action: action, offset: offset, client: client)
        } catch let refused as ElunoError where refused.status == 409 {
            // The snapshot behind this status may be stale, so settle the state and retry once.
            _ = try? await client.json("PATCH", route, ["action": "pause"])
            return try await requestAccess(route, action: action, offset: offset, client: client)
        }
    }

    private func requestAccess(_ route: String, action: String, offset: Int64, client: PinnedAPI) async throws -> String {
        let access = try await client.json("PATCH", route, ["action": action, "bytes": offset])
        guard let url = access["url"] as? String else { throw ElunoError("Transfer access missing.") }
        return url
    }

    /// Publishes exactly once, and only after the expected byte count is on disk.
    private func publish(_ id: String) throws {
        guard var job = incoming[id], !job.published else { return }
        let written = (try fm.attributesOfItem(atPath: job.partial.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard written == job.size else {
            job.bytes = min(written, job.size)
            incoming[id] = job
            throw ElunoError("The received size didn’t match. Tap Resume to fetch the remainder.")
        }
        try fm.moveItem(at: job.partial, to: job.finalURL)
        job.published = true
        incoming[id] = job
        refreshReceived()
    }

    private func acknowledge(_ id: String, client: PinnedAPI) async throws {
        do {
            _ = try await client.json("PATCH", "/api/transfers/\(id)", ["action": "complete"])
        } catch {
            // The coordinator may have recorded completion even though its reply was lost.
            if incoming[id]?.acknowledged == true {
                finishReceive(id)
                return
            }
            if let refused = error as? ElunoError, refused.status == 409, let status = await authoritativeStatus(of: id, client: client) {
                switch TransferReconciler.decide(published: true, status: status) {
                case .acknowledged:
                    finishReceive(id)
                    return
                case .keepPublishedCopy:
                    finishEnded(id)
                    return
                case .keepWorking, .discardIncomplete:
                    break
                }
            }
            throw error
        }
        finishReceive(id)
    }

    private func authoritativeStatus(of id: String, client: PinnedAPI) async -> String? {
        guard let data = try? await client.data("/api/events?since=-1"), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snapshot.room?.transfers?.first(where: { $0.id == id })?.status
    }

    /// Runs once per job, because it takes the job out of `incoming` first. Photos runs after the
    /// transfer is settled, so a Photos failure can't hold back or repeat the inbox result.
    private func finishReceive(_ id: String) {
        guard let job = incoming.removeValue(forKey: id) else { return }
        transferErrors[id] = nil
        message = "Copy saved. It remains available after disconnecting."
        if job.wantsPhotos {
            Task { await importToPhotos(url: job.finalURL, type: job.type) }
        }
    }

    private func finishEnded(_ id: String) {
        guard incoming.removeValue(forKey: id) != nil else { return }
        transferErrors[id] = nil
        message = "That transfer ended, but your finished copy is safe in the Eluno inbox."
    }

    private func receiveFailed(_ id: String, error: Error, client: PinnedAPI) async {
        // Reconciliation has already handled a transfer that ended on the coordinator.
        if Task.isCancelled, incoming[id] == nil { return }
        let explanation: String
        if incoming[id]?.published == true {
            explanation = "Your copy is saved in the Eluno inbox. Tap Resume to finish confirming it with the sender."
        } else if Task.isCancelled {
            explanation = "Paused. Keep the source shared and resume."
        } else {
            explanation = Self.describeReceiveError(error)
        }
        transferErrors[id] = explanation
        // A separate task can still report the pause after this one was cancelled.
        _ = await Task { try? await client.json("PATCH", "/api/transfers/\(id)", ["action": "pause", "error": explanation]) }.value
    }

    nonisolated private static func describeReceiveError(_ error: Error) -> String {
        let value = error as NSError
        if (value.domain == NSCocoaErrorDomain && value.code == NSFileWriteOutOfSpaceError) || (value.domain == NSPOSIXErrorDomain && value.code == Int(ENOSPC)) {
            return "Not enough device storage. Free some space and tap Resume."
        }
        return error.localizedDescription
    }

    /// Applies each snapshot to local jobs. Only work that truly ended is cancelled, so a completion
    /// snapshot can't interrupt the task still awaiting the same completion's response.
    private func reconcileIncoming(_ transfers: [CopyTransfer]) {
        for t in transfers where t.ended { transferErrors[t.id] = nil }
        for (id, job) in incoming {
            let status = transfers.first(where: { $0.id == id })?.status
            switch TransferReconciler.decide(published: job.published, status: status) {
            case .keepWorking:
                break
            case .acknowledged:
                var settled = job
                settled.acknowledged = true
                incoming[id] = settled
                if transferring[id] == nil { finishReceive(id) }
            case .keepPublishedCopy:
                transferring[id]?.cancel()
                finishEnded(id)
            case .discardIncomplete:
                transferring[id]?.cancel()
                incoming[id] = nil
                try? fm.removeItem(at: job.directory)
            }
        }
    }

    // MARK: - Photos

    func saveToPhotos(_ file: ReceivedFile) {
        Task { await importToPhotos(url: file.url, type: file.type) }
    }

    /// Every outcome leaves the inbox copy in place. In-flight tracking and the saved marker keep a
    /// double tap or a retry from importing the same copy twice by accident.
    private func importToPhotos(url: URL, type: String) async {
        guard !photosInFlight.contains(url) else { return }
        guard ImportRules.isPhotosCompatible(type) else {
            recordPhotosFailure(url, "This file type can’t go in Photos. Your copy is still in the Eluno inbox. Save it using Files.")
            return
        }
        photosInFlight.insert(url)
        photosFailures[url] = nil
        refreshReceived()
        defer {
            photosInFlight.remove(url)
            refreshReceived()
        }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            recordPhotosFailure(url, "Photos access is off, so nothing was added. Your copy is still in the Eluno inbox. Allow access in Settings to try again.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if type.hasPrefix("video/") {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
            fm.createFile(atPath: Self.photosMarker(for: url).path, contents: nil)
            message = "Saved to Photos. Your Eluno inbox copy is unchanged."
        } catch {
            recordPhotosFailure(url, "Photos couldn’t import this format. Your copy is still in the Eluno inbox. You can save it using Files.")
        }
    }

    private func recordPhotosFailure(_ url: URL, _ text: String) {
        photosFailures[url] = text
        message = text
        refreshReceived()
    }

    nonisolated private static func photosMarker(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(StoragePaths.photosMarker)
    }

    // MARK: - Inbox

    func refreshReceived() {
        let folders = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        var files: [ReceivedFile] = []
        for folder in folders {
            let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            for url in contents {
                files.append(ReceivedFile(url: url, photos: photosOutcome(for: url)))
            }
        }
        received = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func photosOutcome(for url: URL) -> PhotosOutcome {
        if photosInFlight.contains(url) { return .inProgress }
        if fm.fileExists(atPath: Self.photosMarker(for: url).path) { return .saved }
        if let failure = photosFailures[url] { return .failed(failure) }
        return .notRequested
    }

    /// Runs at launch, when no transfer can be live. Published copies are kept.
    private func removeAbandonedInboxFolders() {
        for folder in (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [] {
            let visible = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            if visible.isEmpty { try? fm.removeItem(at: folder) }
        }
    }

    func removeReceived(_ file: ReceivedFile) {
        do {
            try fm.removeItem(at: file.url.deletingLastPathComponent())
            photosFailures[file.url] = nil
            refreshReceived()
        } catch {
            message = error.localizedDescription
        }
    }

    func saveCopy(_ file: SharedFile) {
        guard let client = api, !downloading else { return }
        downloading = true
        downloadProgress = 0
        downloadTask = Task {
            let directory = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
            var saved = false
            defer {
                downloading = false
                if !saved { try? fm.removeItem(at: directory) }
            }
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try requireSpace(for: file.size)
                let access = try await client.json("POST", "/api/files/\(file.id)/open", ["purpose": "download"])
                guard let route = access["url"] as? String else { throw ElunoError("Copy access missing.") }
                let partial = directory.appendingPathComponent(StoragePaths.partial)
                fm.createFile(atPath: partial.path, contents: nil)
                do {
                    let output = try FileHandle(forWritingTo: partial)
                    defer { try? output.close() }
                    var offset: Int64 = 0
                    while offset < file.size {
                        try Task.checkCancellation()
                        let end = min(offset + Wire.chunkBytes, file.size) - 1
                        let bytes = try await client.data(route, range: offset...end, total: file.size)
                        try Task.checkCancellation()
                        try output.write(contentsOf: bytes)
                        offset = end + 1
                        downloadProgress = Double(offset) / Double(file.size)
                    }
                    try output.synchronize()
                }
                try fm.moveItem(at: partial, to: directory.appendingPathComponent(FileNames.inboxName(file.name)))
                saved = true
                refreshReceived()
                message = "Copy saved in your Eluno inbox."
            } catch {
                message = Task.isCancelled ? "Download cancelled. Use Send a copy for a resumable transfer." : error.localizedDescription
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    // MARK: - Share Extension queue

    func importShareQueue() {
        guard !preparing, let group = fm.containerURL(forSecurityApplicationGroupIdentifier: StoragePaths.appGroup) else { return }
        let queue = group.appendingPathComponent("Incoming", isDirectory: true)
        removeAbandonedShareStaging(in: queue)
        let directories = (try? fm.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var imported = 0
        var problem: String?
        for directory in directories.prefix(Wire.maxFilesPerRequest) {
            guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles), let file = files.first else {
                try? fm.removeItem(at: directory)
                continue
            }
            let target = fm.temporaryDirectory.appendingPathComponent("ElunoImports/\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: directory, to: target)
                let url = target.appendingPathComponent(file.lastPathComponent)
                let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
                let name = FileNames.inboxName(url.lastPathComponent)
                let type = Self.mimeType(forName: name)
                try ImportRules.validate(name: name, type: type, size: size)
                let file = PreparedFile(url: url, name: name, type: type, size: size)
                prepared.append(file)
                imported += 1
                Task { await addFormat(to: file) }
            } catch {
                try? fm.removeItem(at: target)
                problem = error.localizedDescription
            }
        }
        if let problem {
            message = "\(problem) Select it inside Eluno using Files instead."
        } else if imported > 0 {
            message = room == nil
                ? "Content from another app is ready. Connect and review the selection before sharing."
                : "Content from another app is ready. Review the selection before sharing."
        }
    }

    private func addFormat(to file: PreparedFile) async {
        let inspected = await Self.inspected(file)
        if let index = prepared.firstIndex(where: { $0.id == file.id }) { prepared[index].format = inspected.format }
    }

    /// Clears staging left by an extension the system ended mid-copy. The age check leaves a copy
    /// that may still be running alone.
    private func removeAbandonedShareStaging(in queue: URL) {
        let entries = (try? fm.contentsOfDirectory(at: queue, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries where entry.lastPathComponent.hasPrefix(StoragePaths.pendingSharePrefix) {
            if let created = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate, created < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // MARK: - Viewing

    func open(_ file: SharedFile) {
        closeViewer()
        guard let client = api else { return }
        viewing = file
        viewTask = Task {
            do {
                let access = try await client.json("POST", "/api/files/\(file.id)/open")
                guard let route = access["url"] as? String else { throw ElunoError("This item is unavailable.") }
                try Task.checkCancellation()
                if file.type.hasPrefix("video/") {
                    startVideo(file, route: route, client: client)
                } else {
                    guard file.size <= Wire.maxPhotoBytes else { throw ElunoError("This photo is too large to preview.") }
                    var bytes = Data()
                    var offset: Int64 = 0
                    while offset < file.size {
                        let end = min(offset + Wire.chunkBytes, file.size) - 1
                        let chunk = try await client.data(route, range: offset...end, total: file.size)
                        bytes.append(chunk)
                        offset = end + 1
                        try Task.checkCancellation()
                    }
                    let encoded = bytes
                    let image = await Task.detached(priority: .userInitiated) { Self.previewImage(encoded) }.value
                    try Task.checkCancellation()
                    guard let image else { throw ElunoError("This device can’t display the original format. Ask the sender to share a JPEG or PNG version, or save a copy.") }
                    photo = UIImage(cgImage: image)
                }
            } catch {
                if !Task.isCancelled { viewerError = error.localizedDescription }
            }
        }
    }

    private func startVideo(_ file: SharedFile, route: String, client: PinnedAPI) {
        // Plays sound even with the Ring/Silent switch off, as people expect from a video.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let loader = PinnedPlayer(api: client, route: route, file: file)
        self.loader = loader
        let next = loader.makePlayer()
        player = next
        playerObservation = next.currentItem?.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self.viewerError = "This video can’t play on this device. HEVC, MOV and WebM support varies. Ask the sender for an H.264/AAC MP4, or save a copy if they allow it."
            }
        }
        if let position = positions[file.id] { next.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
        next.play()
    }

    nonisolated private static func previewImage(_ bytes: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func closeViewer() {
        if let id = viewing?.id, let seconds = player?.currentTime().seconds, seconds.isFinite { positions[id] = seconds }
        viewTask?.cancel()
        playerObservation = nil
        if player != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        player?.pause()
        player = nil
        loader?.stop()
        loader = nil
        photo = nil
        viewerError = nil
        viewing = nil
    }

    // MARK: - Lifecycle

    func foreground(_ value: Bool) {
        guard value != active else { return }
        active = value
        if value {
            importShareQueue()
            refreshReceived()
        } else {
            player?.pause()
            if downloading || !transferring.isEmpty {
                downloadTask?.cancel()
                transferring.values.forEach { $0.cancel() }
                message = "Transfers pause when Eluno leaves the foreground. Reopen and tap Resume."
            }
        }
    }

    private func stopSessionWork(keepSelection: Bool = false) {
        closeViewer()
        cancelPreparation()
        cancelDownload()
        if !keepSelection { discardPrepared() }
        serving.values.forEach { $0.cancel() }
        serving.removeAll()
        favorites.removeAll()
        transferring.values.forEach { $0.cancel() }
        transferring.removeAll()
        busyTransfers.removeAll()
        transferErrors.removeAll()
        for source in sources.values { try? fm.removeItem(at: source.url.deletingLastPathComponent()) }
        sources.removeAll()
        for job in incoming.values where !job.published { try? fm.removeItem(at: job.directory) }
        incoming.removeAll()
        positions.removeAll()
        identityToRemember = nil
        health = nil
    }

    /// Ends a session the coordinator already closed, so no goodbye is sent to it.
    private func endSession(_ text: String, keepSelection: Bool = false) {
        generation = UUID()
        connection?.cancel()
        polling?.cancel()
        let old = api
        api = nil
        room = nil
        pending = false
        connecting = false
        stopSessionWork(keepSelection: keepSelection)
        old?.close()
        message = text
    }

    func disconnect() {
        generation = UUID()
        connection?.cancel()
        polling?.cancel()
        let old = api
        api = nil
        room = nil
        pending = false
        connecting = false
        stopSessionWork()
        if let old {
            Task {
                _ = try? await old.json("POST", "/api/leave", timeout: 5)
                old.close()
            }
        }
        message = "Disconnected. Received copies remain in your inbox."
    }
}
