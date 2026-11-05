import AVFoundation
import UniformTypeIdentifiers

// AVPlayer's resource loader routes every byte range through the paired TLS session.
final class PinnedPlayer: NSObject, AVAssetResourceLoaderDelegate {
    let api: PinnedAPI; let route: String; let file: SharedFile
    private let queue = DispatchQueue(label: "app.eluno.player")
    // Touched only on `queue`, which is also the resource loader's delegate queue.
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var stopped = false

    init(api: PinnedAPI, route: String, file: SharedFile) { self.api = api; self.route = route; self.file = file }

    func makePlayer() -> AVPlayer {
        let asset = AVURLAsset(url: URL(string: "eluno-stream://media/\(file.id)")!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        // Requests can still arrive after a source is removed or the viewer closes. Start no new range work.
        guard !stopped else { return false }
        let id = ObjectIdentifier(request)
        request.contentInformationRequest?.contentType = UTType(mimeType: file.type)?.identifier ?? UTType.movie.identifier
        request.contentInformationRequest?.contentLength = file.size
        request.contentInformationRequest?.isByteRangeAccessSupported = true
        guard let dataRequest = request.dataRequest else { request.finishLoading(); return true }
        let start = max(dataRequest.requestedOffset, dataRequest.currentOffset)
        let end = dataRequest.requestsAllDataToEndOfResource ? file.size : min(file.size, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                var offset = start
                while offset < end {
                    try Task.checkCancellation()
                    let last = min(offset + Wire.chunkBytes, end) - 1
                    let bytes = try await api.data(route, range: offset...last, total: file.size)
                    try Task.checkCancellation()
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        queue.async { if !request.isCancelled { dataRequest.respond(with: bytes) }; continuation.resume() }
                    }
                    offset = last + 1
                }
                queue.async { if !request.isCancelled { request.finishLoading() }; self.tasks.removeValue(forKey: id) }
            } catch { queue.async { if !request.isCancelled { request.finishLoading(with: error) }; self.tasks.removeValue(forKey: id) } }
        }
        return true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.tasks.values.forEach { $0.cancel() }
            self.tasks.removeAll()
        }
    }
}
