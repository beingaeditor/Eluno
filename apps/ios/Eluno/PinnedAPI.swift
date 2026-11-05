import Foundation
import Security
import CryptoKit

final class PinnedAPI: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Room snapshots and JSON replies stay far below this. Nothing else is read without a known length.
    static let responseLimit = 4 * 1024 * 1024
    /// Room for a JSON error body on a very small range, such as AVPlayer's two-byte probe.
    private static let errorBodyAllowance = 64 * 1024

    let origin: URL
    let fingerprint: String
    var token: String?
    var deviceID = ""

    private final class Load {
        let limit: Int
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var body = Data()
        var response: HTTPURLResponse?
        var overflowed = false
        init(limit: Int, continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
            self.limit = limit; self.continuation = continuation
        }
    }

    /// Lets Swift task cancellation reach a URLSession task that may not exist yet.
    private final class TaskHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false
        func attach(_ task: URLSessionTask) {
            lock.lock(); self.task = task; let cancelNow = cancelled; lock.unlock()
            if cancelNow { task.cancel() }
        }
        func cancel() {
            lock.lock(); cancelled = true; let current = task; lock.unlock()
            current?.cancel()
        }
    }

    private let lock = NSLock()
    private var loads: [Int: Load] = [:]
    private var closed = false
    private var identityRejected = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 8
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(endpoint: String, fingerprint: String) throws {
        self.origin = try Endpoint.validate(endpoint)
        guard fingerprint.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { throw ElunoError("Invalid computer identity.") }
        self.fingerprint = fingerprint.lowercased()
        super.init()
    }

    // MARK: Certificate pin

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard challenge.protectionSpace.host == origin.host, challenge.protectionSpace.port == origin.port,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            rejectIdentity(completionHandler)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard digest == fingerprint else {
            rejectIdentity(completionHandler)
            return
        }
        // This app trusts only the scanned certificate. Basic X.509 evaluation still checks validity dates.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else {
            rejectIdentity(completionHandler)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func rejectIdentity(_ completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        lock.lock(); identityRejected = true; lock.unlock()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    // MARK: Bounded response reads

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let load = load(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        load.response = response as? HTTPURLResponse
        if response.expectedContentLength > Int64(load.limit) {
            load.overflowed = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let load = load(for: dataTask), !load.overflowed else { return }
        if load.body.count + data.count > load.limit {
            load.overflowed = true
            dataTask.cancel()
            return
        }
        load.body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let finished = loads.removeValue(forKey: task.taskIdentifier)
        let rejected = identityRejected
        lock.unlock()
        guard let finished else { return }
        if finished.overflowed {
            finished.continuation.resume(throwing: ElunoError("Your computer sent more data than this request allows. Reconnect and try again.", kind: .tooLarge))
        } else if let error {
            finished.continuation.resume(throwing: Self.translate(error, identityRejected: rejected))
        } else if let response = finished.response {
            finished.continuation.resume(returning: (finished.body, response))
        } else {
            finished.continuation.resume(throwing: ElunoError("Unexpected server response.", kind: .unreachable))
        }
    }

    private func load(for task: URLSessionTask) -> Load? {
        lock.lock(); defer { lock.unlock() }
        return loads[task.taskIdentifier]
    }

    private static func translate(_ error: Error, identityRejected: Bool) -> Error {
        if identityRejected { return ElunoError(PairingFailure.identityMessage, kind: .identityChanged) }
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cancelled:
            return urlError
        case .notConnectedToInternet:
            // The usual result when Local Network access is denied or its alert is still showing.
            return ElunoError(PairingFailure.localNetworkMessage, kind: .localNetwork)
        default:
            return ElunoError("Connection interrupted. Keep both devices open and try again.", kind: .unreachable)
        }
    }

    // MARK: Requests

    private func send(_ request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let handle = TaskHandle()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                lock.lock()
                // URLSession raises an exception for a task created after invalidation, so this check and
                // the creation below must be atomic with close().
                guard !closed else {
                    lock.unlock()
                    continuation.resume(throwing: ElunoError("This connection has ended.", kind: .disconnected))
                    return
                }
                let task = session.dataTask(with: request)
                loads[task.taskIdentifier] = Load(limit: limit, continuation: continuation)
                lock.unlock()
                handle.attach(task)
                task.resume()
            }
        }, onCancel: {
            handle.cancel()
        })
    }

    func data(_ route: String, method: String = "GET", body: Data? = nil, range: ClosedRange<Int64>? = nil, total: Int64? = nil, json: Bool = false, timeout: TimeInterval? = nil) async throws -> Data {
        guard route.hasPrefix("/"), !route.hasPrefix("//"), let url = URL(string: origin.absoluteString + route), url.host == origin.host, url.port == origin.port else { throw ElunoError("Invalid request.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let timeout { request.timeoutInterval = timeout }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if body != nil { request.setValue(json ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type") }
        var limit = Self.responseLimit
        if let range {
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
            limit = max(Int(range.upperBound - range.lowerBound + 1), Self.errorBodyAllowance)
        }
        let (bytes, http) = try await send(request, limit: limit)
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            throw ElunoError(error?["error"] as? String ?? "Connection interrupted. Keep both devices open and try again.", status: http.statusCode)
        }
        if let range, !ContentRange.verifies(status: http.statusCode, header: http.value(forHTTPHeaderField: "Content-Range"), bodyCount: bytes.count, requested: range, total: total) {
            throw ElunoError("The source changed. Share it again.", kind: .sourceChanged)
        }
        return bytes
    }

    func json(_ method: String, _ route: String, _ values: [String: Any] = [:], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        var body: Data?
        if method != "GET" { body = try JSONSerialization.data(withJSONObject: values) }
        let bytes = try await data(route, method: method, body: body, json: true, timeout: timeout)
        guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw ElunoError("Unexpected server response.") }
        return result
    }

    func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        let current = session
        lock.unlock()
        if !wasClosed { current.invalidateAndCancel() }
    }
}
