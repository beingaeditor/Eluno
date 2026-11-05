import Foundation

// This file and TransferLogic.swift use only Foundation so the unit test target
// can compile them directly, without the app, SwiftUI or a signing identity.

struct Device: Codable, Identifiable { let id: String; let name: String; let online: Bool? }
struct SharedFile: Codable, Identifiable {
    let id: String; let ownerId: String; let name: String; let type: String; let size: Int64; let allowDownload: Bool
    let collection: String?
}
struct CopyTransfer: Codable, Identifiable {
    let id: String; let fileId: String; let senderId: String; let receiverId: String
    let name: String; let type: String; let size: Int64; let bytes: Int64; let status: String; let error: String
    var ended: Bool { TransferStatus.isEnded(status) }
}
struct Room: Codable {
    let id: String; let ownerId: String; let members: [Device]; let files: [SharedFile]; let transfers: [CopyTransfer]?
}
struct ReadRequest: Codable { let id: String; let fileId: String; let start: Int64; let end: Int64 }
struct Snapshot: Codable { let version: Int; let pending: Bool; let room: Room?; let reads: [ReadRequest] }

struct Invitation: Codable {
    static let expiredMessage = "This invitation has expired. Open Connect another device on your computer to get a fresh code."

    let v: Int; let endpoints: [String]; let fingerprint: String; let code: String; let expiresAt: Double

    func isExpired(now: Date = Date()) -> Bool { expiresAt <= now.timeIntervalSince1970 * 1000 }

    static func parse(_ text: String, now: Date = Date()) throws -> Invitation {
        guard text.count < 6000, let url = URLComponents(string: text), url.scheme == "eluno", url.host == "pair",
              var encoded = url.queryItems?.first(where: { $0.name == "data" })?.value else {
            throw ElunoError("This isn’t an Eluno invitation. Open Connect another device on your computer and scan the code it shows.")
        }
        encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), let invite = try? JSONDecoder().decode(Invitation.self, from: data) else {
            throw ElunoError("This invitation is damaged or incomplete. Scan it again, or get a fresh code on your computer.")
        }
        guard invite.v == Wire.protocolVersion else {
            throw ElunoError("This invitation needs a different version of Eluno. Install the same version on both devices.", kind: .incompatible)
        }
        guard !invite.isExpired(now: now) else { throw ElunoError(expiredMessage) }
        guard invite.code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil,
              invite.fingerprint.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              (1...12).contains(invite.endpoints.count) else {
            throw ElunoError("This invitation is damaged or incomplete. Scan it again, or get a fresh code on your computer.")
        }
        for endpoint in invite.endpoints { _ = try Endpoint.validate(endpoint) }
        return invite
    }
}

enum Endpoint {
    /// Accepts only `https://<private IPv4>:<port>`. Anything else is refused before a connection is made.
    static func validate(_ endpoint: String) throws -> URL {
        guard let c = URLComponents(string: endpoint), c.scheme == "https", let host = c.host,
              let port = c.port, (1...65535).contains(port), c.user == nil, c.password == nil,
              c.path.isEmpty, c.query == nil, c.fragment == nil, let url = c.url else {
            throw ElunoError("Use a private-network computer invitation.")
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 4, numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }),
              zip(parts, numbers).allSatisfy({ String($0.1) == $0.0 }),
              numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) || (numbers[0] == 172 && (16...31).contains(numbers[1])) else {
            throw ElunoError("Only private IPv4 network invitations are supported.")
        }
        return url
    }
}

struct ElunoError: LocalizedError {
    enum Kind: Equatable { case general, identityChanged, localNetwork, unreachable, incompatible, disconnected, tooLarge, sourceChanged }

    let message: String
    /// The HTTP status when the coordinator itself answered, so callers can tell a refusal from a lost connection.
    let status: Int?
    let kind: Kind

    init(_ message: String, status: Int? = nil, kind: Kind = .general) {
        self.message = message; self.status = status; self.kind = kind
    }
    var errorDescription: String? { message }
}
