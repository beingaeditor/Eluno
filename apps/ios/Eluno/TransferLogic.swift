import Foundation

/// Values shared with `packages/protocol/index.mjs`. `tests/ios-contract.test.mjs` fails if they drift.
enum Wire {
    static let protocolVersion = 1
    static let chunkBytes: Int64 = 262_144
    static let maxPhotoBytes: Int64 = 52_428_800
    static let maxFilesPerRequest = 50
    static let maxNameUnits = 120
    static let mediaTypes: Set<String> = ["video/mp4", "video/webm", "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "video/quicktime"]
}

enum TransferStatus {
    static func isEnded(_ status: String) -> Bool { ["completed", "cancelled", "declined"].contains(status) }
}

// MARK: - Coordinator capabilities

struct CoordinatorHealth: Equatable {
    let supportsCopies: Bool
    let supportsSaveCopy: Bool

    /// Refuses anything that is not a compatible coordinator, before this device registers with it.
    init(_ values: [String: Any]) throws {
        guard values["product"] as? String == "Eluno" else {
            throw ElunoError("This address isn’t an Eluno computer. Scan a fresh invitation.", kind: .incompatible)
        }
        guard values["protocol"] as? Int == Wire.protocolVersion, values["chunkBytes"] as? Int == Int(Wire.chunkBytes) else {
            throw ElunoError("Your computer runs an incompatible version of Eluno. Install the same version on both devices.", kind: .incompatible)
        }
        let modules = (values["modules"] as? [[String: Any]]) ?? []
        func supports(_ id: String) -> Bool { modules.contains { $0["id"] as? String == id && $0["version"] as? Int == 1 } }
        supportsCopies = supports("transfers")
        supportsSaveCopy = supports("save-copy")
    }
}

// MARK: - Pairing failures

enum PairingFailure {
    static let identityMessage = "This computer’s security identity doesn’t match the invitation, so Eluno did not connect. Scan a fresh invitation from the computer you trust. If you saved this computer, forget it first."
    static let localNetworkMessage = "Eluno couldn’t use your local network. Allow Local Network for Eluno in Settings › Privacy & Security, join the same Wi-Fi as your computer, then scan again."
    static let unreachableMessage = "Could not reach your computer. Use the same private Wi-Fi (not a guest network), keep Eluno open on the computer, check Local Network access in Settings, and scan a fresh invitation."

    /// A reply from the coordinator is final, because another address reaches the same coordinator.
    /// A 403 is the exception: one address may have gone stale while another still works.
    static func isFinal(_ error: Error) -> Bool {
        guard let known = error as? ElunoError else { return false }
        if known.kind == .incompatible { return true }
        guard let status = known.status else { return false }
        return status != 403
    }

    static func message(forFinal error: Error) -> String {
        guard let known = error as? ElunoError else { return error.localizedDescription }
        return known.status == 404 ? Invitation.expiredMessage : known.message
    }

    /// Summarizes the attempts when no address worked. A wrong identity outranks everything else,
    /// because it is the one result that could mean another machine is answering.
    static func summary(_ errors: [Error]) -> String {
        let kinds = errors.compactMap { ($0 as? ElunoError)?.kind }
        if kinds.contains(.identityChanged) { return identityMessage }
        if kinds.contains(.localNetwork) { return localNetworkMessage }
        return unreachableMessage
    }

    /// Errors that mean this session can never recover, so polling should stop.
    static func endsSession(_ error: Error) -> Bool {
        guard let known = error as? ElunoError else { return false }
        return known.status == 401 || known.kind == .identityChanged || known.kind == .disconnected
    }
}

// MARK: - Range responses

struct ContentRange: Equatable {
    let start: Int64; let end: Int64; let total: Int64

    /// Parses only the single form the coordinator sends: `bytes <start>-<end>/<total>`.
    init?(header: String) {
        guard header.hasPrefix("bytes ") else { return nil }
        let parts = header.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]), let total = Int64(parts[1]),
              start >= 0, end >= start, end < total else { return nil }
        self.start = start; self.end = end; self.total = total
    }

    /// A bounded read is usable only as a 206 whose range and length match the request exactly.
    static func verifies(status: Int, header: String?, bodyCount: Int, requested: ClosedRange<Int64>, total: Int64?) -> Bool {
        guard status == 206, let header, let range = ContentRange(header: header) else { return false }
        guard range.start == requested.lowerBound, range.end == requested.upperBound else { return false }
        if let total, range.total != total { return false }
        return Int64(bodyCount) == requested.upperBound - requested.lowerBound + 1
    }
}

// MARK: - Receiving a copy

/// What the receiver has committed locally for one transfer. Inbox publication and coordinator
/// acknowledgement are separate facts, so losing either response can't repeat the other step.
struct IncomingJob {
    let directory: URL
    let partial: URL
    let finalURL: URL
    let type: String
    let size: Int64
    let wantsPhotos: Bool
    var bytes: Int64 = 0
    var published = false
    var acknowledged = false
}

enum ReceiveDecision: Equatable {
    /// The transfer is still live on the coordinator. Leave any running work alone.
    case keepWorking
    /// The coordinator recorded completion of a copy already in the inbox.
    case acknowledged
    /// The transfer ended without an acknowledgement, but the copy is safely in the inbox.
    case keepPublishedCopy
    /// The transfer ended before anything was published. Remove the partial file.
    case discardIncomplete
}

enum TransferReconciler {
    /// A completion snapshot must never cancel a task that is still awaiting the completion response.
    static func decide(published: Bool, status: String?) -> ReceiveDecision {
        guard let status else { return published ? .keepPublishedCopy : .discardIncomplete }
        if !TransferStatus.isEnded(status) { return .keepWorking }
        if !published { return .discardIncomplete }
        return status == "completed" ? .acknowledged : .keepPublishedCopy
    }
}

// MARK: - Names and imports

enum FileNames {
    private static let disallowed = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)

    /// A name safe to publish in the inbox. Hidden names are prefixed because the inbox skips hidden files,
    /// which also keeps a sender from colliding with Eluno's own `.eluno.*` markers.
    static func inboxName(_ name: String) -> String {
        var value = name.components(separatedBy: disallowed).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        let hidden = value.hasPrefix(".")
        while value.hasPrefix(".") { value.removeFirst() }
        if value.isEmpty { return "Eluno-file" }
        return truncated(hidden ? "Eluno-" + value : value)
    }

    /// Bounds a name to the coordinator's 120 UTF-16 units and the file system's byte limit, keeping the extension.
    static func truncated(_ name: String, maxUnits: Int = Wire.maxNameUnits, maxBytes: Int = 240) -> String {
        func fits(_ value: String) -> Bool { value.utf16.count <= maxUnits && value.utf8.count <= maxBytes }
        if fits(name) { return name }
        let pathExtension = NSString(string: name).pathExtension
        let suffix = pathExtension.isEmpty || pathExtension.utf8.count > 16 ? "" : "." + pathExtension
        var stem = suffix.isEmpty ? name : String(name.dropLast(suffix.count))
        while !stem.isEmpty, !fits(stem + suffix) { stem.removeLast() }
        return stem.isEmpty ? "Eluno-file" : stem + suffix
    }
}

enum ImportRules {
    /// The checks the coordinator would otherwise fail, which reject a whole batch for one bad item.
    static func validate(name: String, type: String, size: Int64) throws {
        guard size > 0 else {
            throw ElunoError("\(name) is empty or unavailable. Download it from iCloud, then select it again.")
        }
        if type.hasPrefix("image/"), size > Wire.maxPhotoBytes {
            throw ElunoError("\(name) is larger than the 50 MB photo limit. Choose a smaller photo.")
        }
    }

    /// Only these types can be viewed by other devices. Anything else is shared as a copy.
    static func isStreamable(_ type: String) -> Bool { Wire.mediaTypes.contains(type) }

    static func isPhotosCompatible(_ type: String) -> Bool { type.hasPrefix("image/") || type.hasPrefix("video/") }
}

// MARK: - Actual media formats

struct MediaFormat: Equatable {
    let summary: String
    /// True only for what every Eluno client can play: JPEG, PNG and H.264/AAC MP4.
    let interoperable: Bool

    static func image(mime: String) -> MediaFormat {
        switch mime {
        case "image/jpeg": return MediaFormat(summary: "JPEG", interoperable: true)
        case "image/png": return MediaFormat(summary: "PNG", interoperable: true)
        case "image/heic", "image/heif": return MediaFormat(summary: "HEIC", interoperable: false)
        case "image/webp": return MediaFormat(summary: "WebP", interoperable: false)
        default: return MediaFormat(summary: "Copy only", interoperable: false)
        }
    }

    /// Reports what was actually returned, using the four-character codec codes from the file's tracks.
    static func video(mime: String, videoCodecs: [String], audioCodecs: [String]) -> MediaFormat {
        guard !videoCodecs.isEmpty else { return MediaFormat(summary: "Format not confirmed", interoperable: false) }
        let container: String
        switch mime {
        case "video/mp4": container = "MP4"
        case "video/quicktime": container = "MOV"
        case "video/webm": container = "WebM"
        default: container = "video file"
        }
        let isH264 = videoCodecs.allSatisfy { $0 == "avc1" }
        let isHEVC = videoCodecs.contains(where: { $0 == "hvc1" || $0 == "hev1" })
        let isAAC = audioCodecs.allSatisfy { $0 == "aac " }
        let video = isH264 ? "H.264" : (isHEVC ? "HEVC" : "Other video")
        let audio = audioCodecs.isEmpty ? "" : (isAAC ? "/AAC" : "/other audio")
        return MediaFormat(summary: "\(video)\(audio) \(container)", interoperable: mime == "video/mp4" && isH264 && isAAC)
    }
}

// MARK: - Outcomes the inbox shows

/// Tracked per inbox file, separately from the transfer that produced it.
enum PhotosOutcome: Equatable {
    case notRequested, inProgress, saved
    case failed(String)
}

/// A cancellation flag that background picker callbacks can read safely.
/// Each import gets its own, so a superseded callback can never touch the next import's state.
final class ImportToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}
