@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import Vision
import simd
import SwiftUI

struct CapturedPhoto: Sendable {
    let data: Data
    let calibration: CameraCalibration?
}

struct CameraCapture: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (CapturedPhoto) -> Void

    func makeUIViewController(context: Context) -> CalibratedCameraController {
        let controller = CalibratedCameraController()
        controller.onCapture = { photo in dismiss(); onCapture(photo) }
        controller.onCancel = { dismiss() }
        return controller
    }
    func updateUIViewController(_ controller: CalibratedCameraController, context: Context) {}
    static func dismantleUIViewController(_ controller: CalibratedCameraController, coordinator: ()) { controller.stop() }
}

@MainActor
final class CalibratedCameraController: UIViewController {
    var onCapture: ((CapturedPhoto) -> Void)?
    var onCancel: (() -> Void)?
    private var camera: CalibratedCameraSession!
    private var preview: AVCaptureVideoPreviewLayer!
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let autoButton = UIButton(type: .system)
    private var automatic = CapturePreferences.automaticShutter
    private var rotationObservation: NSKeyValueObservation?
    private let shutter = UIButton(type: .system)
    private let status = UILabel()
    private let guidance = UILabel()
    private var active = true
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        camera = CalibratedCameraSession { [weak self] event in
            guard let self, active else { return }
            switch event {
            case .ready(let calibrated):
                shutter.isEnabled = true
                view.setNeedsLayout()
                status.text = automatic ? "Show the whole card — auto captures a sharp frame" : (calibrated ? "Automatic proportions ready" : "Choose proportions after capture")
            case .quality(let quality): status.text = quality.rawValue
            case .capturing:
                shutter.isEnabled = false; autoButton.isEnabled = false; status.text = "Capturing…"
            case .photo(let photo): onCapture?(photo)
            case .failure(let message):
                shutter.isEnabled = false; autoButton.isEnabled = false; status.text = message
            }
        }
        camera.setAutomatic(automatic)
        preview = AVCaptureVideoPreviewLayer(session: camera.session)
        preview.videoGravity = .resizeAspect // Show the entire captured frame, with no preview crop.
        view.layer.addSublayer(preview)
        if let device = camera.device {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.view.setNeedsLayout() }
            }
        }
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        shutter.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)), for: .normal)
        shutter.tintColor = .white
        shutter.accessibilityLabel = "Take photo"
        shutter.isEnabled = false
        shutter.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            camera.capture(rotationAngle: Double(preview.connection?.videoRotationAngle ?? 0))
        }, for: .touchUpInside)
        autoButton.setTitle(automatic ? "Auto: On" : "Auto: Off", for: .normal)
        autoButton.tintColor = .white
        autoButton.accessibilityLabel = "Automatic capture"
        autoButton.accessibilityValue = automatic ? "On" : "Off"
        autoButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            automatic.toggle()
            CapturePreferences.automaticShutter = automatic
            updateGuidance()
            autoButton.setTitle(automatic ? "Auto: On" : "Auto: Off", for: .normal)
            autoButton.accessibilityValue = automatic ? "On" : "Off"
            camera.setAutomatic(automatic)
            status.text = automatic ? "Show the whole card — auto captures a sharp frame" : "Tap the shutter when ready"
        }, for: .touchUpInside)
        status.text = "Starting camera…"
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.textColor = .white
        status.numberOfLines = 0
        status.textAlignment = .center
        updateGuidance()
        guidance.font = .preferredFont(forTextStyle: .subheadline)
        guidance.textColor = .white
        guidance.textAlignment = .center
        guidance.numberOfLines = 0
        for item in [cancel, autoButton, shutter, status, guidance] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            autoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            autoButton.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            autoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutter.widthAnchor.constraint(equalToConstant: 84), shutter.heightAnchor.constraint(equalToConstant: 84),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            status.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -14),
            guidance.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 12),
            guidance.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            guidance.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        camera.start()
    }
    private func updateGuidance() {
        guidance.text = automatic ? "Keep the whole card visible. Auto chooses a sharp frame." : "Keep the whole card visible, then tap the shutter."
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        if let connection = preview.connection {
            let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 0
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
                camera.updateRotation(Double(angle)) // Encode what the user sees in this portrait preview.
            }
        }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); stop() }
    func stop() { active = false; camera?.stop() }
}

/// AVFoundation is confined to one serial queue, including frame callbacks. The immutable
/// session reference is exposed only to AVCaptureVideoPreviewLayer on the UI thread.
private final class CalibratedCameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event: Sendable { case ready(Bool), quality(AutoCaptureGate.Status), capturing, photo(CapturedPhoto), failure(String) }
    let session = AVCaptureSession()
    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private let queue = DispatchQueue(label: "CardStraight.camera", qos: .userInitiated)
    private let onEvent: @MainActor @Sendable (Event) -> Void
    private let context = CIContext()
    private var automatic = true
    private var completed = false
    private var stopped = false
    private var gate = AutoCaptureGate()
    private var lastAnalysis = -Double.infinity
    private var lastQuality: AutoCaptureGate.Status?
    private var configured = false
    private var pendingCapture = false
    private var captureOrientation = 1
    private var rotationReady = false
    private var reportedCalibration: Bool?
    private var observers = [NSObjectProtocol]()

    init(onEvent: @escaping @MainActor @Sendable (Event) -> Void) { self.onEvent = onEvent; super.init() }
    private func report(_ event: Event) { Task { @MainActor [onEvent] in onEvent(event) } }
    func start() {
        queue.async { [self] in
            do {
                if !configured { try configure(); configured = true }
                stopped = false
                session.startRunning()
                if !session.isRunning { report(.failure("Camera couldn’t start. Close it and try again.")) }
            } catch { report(.failure("Camera unavailable. Close it and choose a photo from your library.")) }
        }
    }
    func stop() {
        queue.async { [self] in
            stopped = true
            pendingCapture = false
            gate.reset()
            if session.isRunning { session.stopRunning() }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
    }
    func capture(rotationAngle: Double) {
        queue.async { [self] in
            guard session.isRunning, !pendingCapture, !completed, !stopped else { return }
            // Keep sensor pixels untouched and carry a cardinal EXIF orientation alongside K.
            // Small horizon roll is handled by the quadrilateral warp, without cropping the frame.
            let turns = (Int((rotationAngle / 90).rounded()) % 4 + 4) % 4
            captureOrientation = [1, 6, 3, 8][turns]
            rotationReady = true
            pendingCapture = true
            report(.capturing)
            queue.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, pendingCapture else { return }
                pendingCapture = false
                report(.failure("Camera was interrupted. Close it and try again."))
            }
        }
    }
    func updateRotation(_ angle: Double) {
        queue.async { [self] in
            guard !pendingCapture, !completed else { return }
            let orientation = [1, 6, 3, 8][(Int((angle / 90).rounded()) % 4 + 4) % 4]
            if captureOrientation != orientation { gate.reset() }
            captureOrientation = orientation
            rotationReady = true
        }
    }
    func setAutomatic(_ enabled: Bool) {
        queue.async { [self] in
            automatic = enabled; gate.reset(); lastQuality = nil
        }
    }

    private func automaticStatus(_ buffer: CVPixelBuffer, time: Double) -> AutoCaptureGate.Status {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.55
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1
        request.minimumSize = 0.15
        request.maximumObservations = 4
        request.quadratureTolerance = 35
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            let observations = (request.results ?? []).filter {
                let b = $0.boundingBox
                return b.minX > 0.015 && b.minY > 0.015 && b.maxX < 0.985 && b.maxY < 0.985 &&
                    b.width * b.height >= 0.07 && abs(b.midX - 0.5) < 0.35 && abs(b.midY - 0.5) < 0.35
            }
            guard let card = observations.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
                return gate.assess(time: time, corners: nil, sharpness: 0, brightness: 0, adjusting: false)
            }
            let corners = [card.topLeft, card.topRight, card.bottomRight, card.bottomLeft].map { CardPoint(x: $0.x, y: $0.y) }
            let image = CIImage(cvPixelBuffer: buffer)
            let b = card.boundingBox
            // Analyze the interior, excluding the sharp outline and surrounding table.
            let crop = CGRect(x: b.minX * image.extent.width, y: b.minY * image.extent.height,
                              width: b.width * image.extent.width, height: b.height * image.extent.height)
                .insetBy(dx: b.width * image.extent.width * 0.18, dy: b.height * image.extent.height * 0.18)
            let patch = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: 256 / crop.width, y: 256 / crop.height))
            var pixels = [UInt8](repeating: 0, count: 256 * 256)
            context.render(patch, toBitmap: &pixels, rowBytes: 256, bounds: CGRect(x: 0, y: 0, width: 256, height: 256),
                           format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
            let detail = FrameDetail.measure(pixels, width: 256, height: 256)
            return gate.assess(time: time, corners: corners, sharpness: detail.sharpness,
                               brightness: detail.brightness, adjusting: device?.isAdjustingFocus == true)
        } catch { return gate.assess(time: time, corners: nil, sharpness: 0, brightness: 0, adjusting: false) }
    }

    private func configure() throws {
        guard let device else { throw CardError.invalidImage }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // A physical wide lens avoids automatic lens switching. Freeze a 4K frame when supported.
        session.sessionPreset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CardError.invalidImage }
        session.addInput(input)
        try device.lockForConfiguration()
        device.videoZoomFactor = 1
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = true }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CardError.invalidImage }
        session.addOutput(output)
        guard let connection = output.connection(with: .video) else { throw CardError.invalidImage }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        // Keep buffer pixels in sensor orientation; each capture records the camera-reported rotation in EXIF.
        if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if !connection.isCameraIntrinsicMatrixDeliverySupported, session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        if connection.isCameraIntrinsicMatrixDeliverySupported { connection.isCameraIntrinsicMatrixDeliveryEnabled = true }
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.stopped = true
                    self?.gate.reset()
                    self?.pendingCapture = false
                    self?.reportedCalibration = nil
                    self?.report(.failure("Camera interrupted. Close it and try again."))
                }
            })
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopped, !completed, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if automatic, rotationReady, !pendingCapture {
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            if time - lastAnalysis >= 0.18 {
                lastAnalysis = time
                let quality = automaticStatus(buffer, time: time)
                if quality != lastQuality { lastQuality = quality; report(.quality(quality)) }
                if quality == .capture { pendingCapture = true; report(.capturing) }
            }
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var calibration: CameraCalibration?
        if let data = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data,
           data.count >= MemoryLayout<matrix_float3x3>.size {
            let matrix = data.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
            let value = CameraCalibration(focalX: Double(matrix.columns.0.x), focalY: Double(matrix.columns.1.y),
                                          centerX: Double(matrix.columns.2.x), centerY: Double(matrix.columns.2.y),
                                          width: Double(width), height: Double(height), orientation: captureOrientation)
            if value.isValid { calibration = value }
        }
        if !pendingCapture, reportedCalibration != (calibration != nil) {
            reportedCalibration = calibration != nil
            report(.ready(calibration != nil))
        }
        guard pendingCapture else { return }
        pendingCapture = false
        completed = true // Both shutter and auto capture freeze this exact frame, once.
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { report(.failure("Couldn’t capture this frame. Try again.")); return }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { report(.failure("Couldn’t encode this photo.")); return }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.98,
                                                        kCGImagePropertyOrientation: captureOrientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { report(.failure("Couldn’t encode this photo.")); return }
        report(.photo(CapturedPhoto(data: data as Data, calibration: calibration)))
    }
}
