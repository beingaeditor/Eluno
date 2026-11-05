import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let progress = Progress(totalUnitCount: 1)
    private let label = UILabel()
    private let send = UIButton(type: .system)
    private var started = false
    /// Lets Cancel take back items this share has already queued.
    private var queued: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.93, alpha: 1)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Prepare selected files for Eluno. Open Eluno afterward to connect and review them before sharing."
        send.setTitle("Prepare for Eluno", for: .normal)
        send.addTarget(self, action: #selector(prepareTapped), for: .touchUpInside)
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, send, cancelButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func cancelTapped() {
        progress.cancel()
        // A cancelled share leaves nothing behind for Eluno to import.
        for item in queued { try? FileManager.default.removeItem(at: item) }
        queued.removeAll()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    @objc private func prepareTapped() {
        guard !started else { return }
        started = true
        send.isEnabled = false
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.eluno.shared") else {
            label.text = "Shared storage is unavailable. Open Eluno and choose your files there. The app owner must configure the shared App Group when signing."
            return
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty, providers.count <= 50 else {
            label.text = "Choose between 1 and 50 files."
            return
        }
        progress.totalUnitCount = Int64(providers.count)
        prepareItem(providers, index: 0, root: root.appendingPathComponent("Incoming", isDirectory: true))
    }

    private func prepareItem(_ providers: [NSItemProvider], index: Int, root: URL) {
        if progress.isCancelled { return }
        if index == providers.count {
            finish("Ready. Open Eluno to review and share your selected files.")
            return
        }
        label.text = "Preparing file \(index + 1) of \(providers.count)…"
        let provider = providers[index]
        // A shared file can also register a URL type, which conforms to data but isn't the file's contents.
        guard let type = provider.registeredTypeIdentifiers.first(where: { Self.isFileType($0) }) else {
            stop("This app did not provide a file. Save it to Files, then select it inside Eluno.")
            return
        }
        let progress = self.progress
        let child = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            // The provider deletes this temporary file when the callback returns, so copy it here.
            let outcome = Result { try Self.enqueue(url, error: error, root: root, progress: progress) }
            Task { @MainActor in
                self.itemFinished(outcome, providers: providers, index: index, root: root)
            }
        }
        progress.addChild(child, withPendingUnitCount: 1)
    }

    private func itemFinished(_ outcome: Result<URL, Error>, providers: [NSItemProvider], index: Int, root: URL) {
        switch outcome {
        case .success(let folder):
            if progress.isCancelled {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            queued.append(folder)
            prepareItem(providers, index: index + 1, root: root)
        case .failure(let error):
            stop(error.localizedDescription + " Any already-prepared files can be reviewed in Eluno.")
        }
    }

    nonisolated private static func isFileType(_ identifier: String) -> Bool {
        guard let candidate = UTType(identifier) else { return false }
        return candidate.conforms(to: .data) && !candidate.conforms(to: .url)
    }

    /// Copies one item into private staging and moves the finished folder into the queue.
    /// That move is what makes an item visible to Eluno, so partial files never are.
    nonisolated private static func enqueue(_ url: URL?, error: Error?, root: URL, progress: Progress) throws -> URL {
        let fm = FileManager.default
        let key = UUID().uuidString
        let staging = root.appendingPathComponent(".pending-" + key, isDirectory: true)
        let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        do {
            if let error { throw error }
            guard let url else { throw NSError(domain: "Eluno", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected file is unavailable."]) }
            if progress.isCancelled { throw cancelled }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let name = url.lastPathComponent.hasPrefix(".") ? "Eluno-" + url.lastPathComponent : url.lastPathComponent
            let destination = staging.appendingPathComponent(name)
            fm.createFile(atPath: destination.path, contents: nil)
            do {
                let input = try FileHandle(forReadingFrom: url)
                let output = try FileHandle(forWritingTo: destination)
                defer {
                    try? input.close()
                    try? output.close()
                }
                var finished = false
                while !finished {
                    // Extensions have a small memory limit, so each chunk's buffer is released right away.
                    try autoreleasepool {
                        if progress.isCancelled { throw cancelled }
                        if let bytes = try input.read(upToCount: 262144), !bytes.isEmpty {
                            try output.write(contentsOf: bytes)
                        } else {
                            finished = true
                        }
                    }
                }
                try output.synchronize()
            }
            if progress.isCancelled { throw cancelled }
            let folder = root.appendingPathComponent(key, isDirectory: true)
            try fm.moveItem(at: staging, to: folder)
            return folder
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Reports a problem and stops. Finished items stay queued, so Done is offered when there are any.
    private func stop(_ text: String) {
        if progress.isCancelled { return }
        if queued.isEmpty {
            label.text = text
        } else {
            finish(text)
        }
    }

    private func finish(_ text: String) {
        label.text = text
        send.setTitle("Done", for: .normal)
        send.isEnabled = true
        send.removeTarget(self, action: #selector(prepareTapped), for: .touchUpInside)
        send.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
    }

    @objc private func doneTapped() { extensionContext?.completeRequest(returningItems: nil) }
}
