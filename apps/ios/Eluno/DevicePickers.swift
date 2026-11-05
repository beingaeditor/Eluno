import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct PhotoSelection: UIViewControllerRepresentable {
    let compatible: Bool
    let selected: ([NSItemProvider]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos]); configuration.selectionLimit = 50
        configuration.preferredAssetRepresentationMode = compatible ? .compatible : .current
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: ([NSItemProvider]) -> Void
        init(_ selected: @escaping ([NSItemProvider]) -> Void) { self.selected = selected }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { selected(results.map(\.itemProvider)) }
    }
}

struct ExportFiles: UIViewControllerRepresentable {
    let url: URL
    let finished: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void
        init(_ finished: @escaping (Bool) -> Void) { self.finished = finished }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finished(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished(false) }
    }
}

struct InvitationScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    let failed: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(scanned: scanned, failed: failed) }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: ScannerController, coordinator: ()) { uiViewController.stop() }
}
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.eluno.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private var stopped = false
    private let scanned: (String) -> Void
    private let failed: (String) -> Void
    init(scanned: @escaping (String) -> Void, failed: @escaping (String) -> Void) { self.scanned = scanned; self.failed = failed; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(scanned:failed:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else { DispatchQueue.main.async { self.failed("Camera access is off. Enable it in Settings to scan your computer’s invitation.") }; return }
            self.queue.async {
                guard !self.stopped else { return }
                do {
                    guard let device = AVCaptureDevice.default(for: .video) else { throw ElunoError("No camera is available.") }
                    let input = try AVCaptureDeviceInput(device: device), output = AVCaptureMetadataOutput()
                    self.capture.beginConfiguration()
                    guard self.capture.canAddInput(input), self.capture.canAddOutput(output) else { self.capture.commitConfiguration(); throw ElunoError("The camera could not start.") }
                    self.capture.addInput(input); self.capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]; self.capture.commitConfiguration()
                    DispatchQueue.main.async {
                        let layer = AVCaptureVideoPreviewLayer(session: self.capture); layer.videoGravity = .resizeAspectFill; self.preview = layer; self.view.layer.addSublayer(layer); layer.frame = self.view.bounds
                    }
                    self.capture.startRunning()
                } catch { DispatchQueue.main.async { self.failed(error.localizedDescription) } }
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let qr = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = qr.stringValue else { return }
        finished = true; stop(); scanned(value)
    }
    func stop() { queue.async { self.stopped = true; if self.capture.isRunning { self.capture.stopRunning() } } }
}
