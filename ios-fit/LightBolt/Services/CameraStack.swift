import AVFoundation
import Observation
import SwiftUI
import UIKit

nonisolated enum CameraAccess: Equatable, Sendable {
    case undetermined
    case authorized
    case denied
    case noDevice
}

/// Live camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainer {
        let view = PreviewContainer()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewContainer: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Finds a usable capture device, including the external camera the cloud
/// simulator injects from the host webcam.
nonisolated enum CameraDiscovery {
    static func bestDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]
        types.append(.external)

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        return devices.first(where: { $0.position == position })
            ?? devices.first(where: { $0.deviceType == .external })
            ?? devices.first
    }

    static func requestAccess() async -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return bestDevice(position: .back) == nil ? .noDevice : .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return .denied }
            return bestDevice(position: .back) == nil ? .noDevice : .authorized
        @unknown default:
            return .undetermined
        }
    }
}

/// Photo capture pipeline for the nutrition scanner.
@Observable
final class MealCamera {
    let session = AVCaptureSession()
    var access: CameraAccess = .undetermined
    var isTorchOn: Bool = false
    private(set) var isRunning: Bool = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "fit.meal.camera")
    private var isConfigured = false
    private var device: AVCaptureDevice?
    private var delegateRetainer: PhotoDelegate?

    func start() async {
        access = await CameraDiscovery.requestAccess()
        guard access == .authorized else { return }
        configureIfNeeded()
        guard isConfigured else { return }
        let session = session
        await withCheckedContinuation { continuation in
            queue.async {
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        isRunning = session.isRunning
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            isTorchOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch {
            isTorchOn = false
        }
    }

    /// Captures a JPEG downscaled for upload.
    func capturePhoto() async -> Data? {
        guard isConfigured, session.isRunning else { return nil }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .balanced

        let data: Data? = await withCheckedContinuation { continuation in
            let delegate = PhotoDelegate { result in
                continuation.resume(returning: result)
            }
            delegateRetainer = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
        delegateRetainer = nil
        guard let data else { return nil }
        return ImageDownscaler.jpeg(from: data, maxDimension: 1024, quality: 0.72)
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = CameraDiscovery.bestDevice(position: .back) else {
            access = .noDevice
            return
        }
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .photo
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            access = .noDevice
            return
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isConfigured = true
    }
}

/// Bridges the AVFoundation delegate callback back into async/await.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Data?) -> Void
    private var hasFinished = false

    init(completion: @escaping @Sendable (Data?) -> Void) {
        self.completion = completion
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard !hasFinished else { return }
        hasFinished = true
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

nonisolated enum ImageDownscaler {
    /// Re-encodes a JPEG so uploads stay small and fast.
    static func jpeg(from data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) ?? data }

        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality) ?? data
    }

    static func thumbnail(from data: Data, side: CGFloat = 240) -> Data? {
        jpeg(from: data, maxDimension: side, quality: 0.6)
    }
}
