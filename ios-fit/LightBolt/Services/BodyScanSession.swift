import AVFoundation
import CoreImage
import CoreVideo
import Observation
import UIKit
import Vision

/// The four poses captured across one full turn. Front and back frames supply
/// body widths; the two side frames supply body depths.
nonisolated enum ScanPose: Int, CaseIterable, Sendable {
    case front, right, back, left

    var label: String {
        switch self {
        case .front: "Front"
        case .right: "Right side"
        case .back: "Back"
        case .left: "Left side"
        }
    }

    /// Point in the capture window where this pose should be facing the lens.
    var progressMark: Double {
        switch self {
        case .front: 0.05
        case .right: 0.30
        case .back: 0.55
        case .left: 0.80
        }
    }
}

/// Measurements solved by the on-device engine. Every value is real-world
/// centimetres, computed locally on the user's chip.
nonisolated struct BodyScanResult: Sendable {
    let chestCm: Double
    let waistCm: Double
    let hipCm: Double
    let shoulderCm: Double
    let thighCm: Double
    let bodyFatPercent: Double?
    let confidence: Double
    let provider: String
    let frameCount: Int
}

/// Stats the local engine needs alongside the frames to solve for scale.
nonisolated struct BodyScanSubject: Sendable {
    let heightCm: Double
    let weightKg: Double
    let age: Int
    let isFemale: Bool

    var isComplete: Bool { heightCm >= 80 && heightCm <= 250 && weightKg >= 25 && weightKg <= 350 }
}

nonisolated enum ScanPhase: Equatable, Sendable {
    case idle
    case countdown(Int)
    case capturing
    case analyzing
    case finished(BodyScanResult)
    case failed(String)

    static func == (lhs: ScanPhase, rhs: ScanPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.capturing, .capturing), (.analyzing, .analyzing): true
        case let (.countdown(a), .countdown(b)): a == b
        case (.finished, .finished): true
        case let (.failed(a), .failed(b)): a == b
        default: false
        }
    }
}

/// Drives the guided 360° scan: runs the camera, banks four clean keyframes as
/// the user turns, then hands them to `BodyMeasurementEngine` for a fully local
/// solve. Nothing is uploaded — the frames never leave the device.
@Observable
final class BodyScanSession {
    static let captureDuration: Double = 18

    let session = AVCaptureSession()
    var access: CameraAccess = .undetermined
    var phase: ScanPhase = .idle
    var progress: Double = 0
    var isBodyVisible: Bool = false
    /// Poses banked so far — drives the capture checklist in the overlay.
    var capturedPoses: [ScanPose] = []

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "fit.bodyscan.frames")
    private var grabber: FrameGrabber?
    private var frames: [CapturedFrame] = []
    private var isConfigured = false
    private var runTask: Task<Void, Never>?

    func prepare() async {
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
    }

    func teardown() {
        runTask?.cancel()
        runTask = nil
        grabber?.isActive = false
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Countdown → timed 360° capture → on-device measurement.
    func beginScan(subject: BodyScanSubject) {
        guard access == .authorized, isConfigured else { return }
        guard subject.heightCm >= 80 else {
            phase = .failed("Add your height in Profile first — the scanner needs it to solve for scale.")
            return
        }
        guard subject.weightKg >= 25 else {
            phase = .failed("Add your weight in Profile first — the scanner needs it to solve for body composition.")
            return
        }

        frames = []
        capturedPoses = []
        progress = 0

        runTask?.cancel()
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for count in stride(from: 5, through: 1, by: -1) {
                phase = .countdown(count)
                LightBoltChime.countdownBeep()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }

            phase = .capturing
            LightBoltChime.intervalEnd()
            grabber?.isActive = true

            let poses = ScanPose.allCases
            var nextPose = 0
            let start = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                progress = min(1, elapsed / Self.captureDuration)

                if nextPose < poses.count, progress >= poses[nextPose].progressMark {
                    if let jpeg = grabber?.grab() {
                        frames.append(CapturedFrame(pose: poses[nextPose], jpeg: jpeg))
                        capturedPoses.append(poses[nextPose])
                        Haptics.tick()
                    }
                    nextPose += 1
                }

                if elapsed >= Self.captureDuration { break }
                try? await Task.sleep(for: .milliseconds(60))
            }

            grabber?.isActive = false
            if Task.isCancelled { return }

            guard frames.count >= 2 else {
                Haptics.warning()
                phase = .failed("LightBolt couldn't keep your full body in frame. Stand 2–3 m back against a plain wall, then turn slowly through a full circle.")
                return
            }

            phase = .analyzing
            LightBoltChime.sessionComplete()

            // The daily allowance lives on the server so it survives reinstalls,
            // even though the measurement itself is local.
            var didClaimSlot = false
            do {
                try await BackendClient.shared.claimBodyScan()
                didClaimSlot = true
            } catch let error as BackendError {
                if case .quotaReached = error {
                    Haptics.warning()
                    phase = .failed(error.localizedDescription)
                    return
                }
                // Offline or a server hiccup: measuring needs no network, so the
                // scan proceeds and the tab's own history gate holds the cap.
                print("[BodyScan] allowance check unavailable, continuing locally")
            } catch {
                print("[BodyScan] allowance check failed, continuing locally")
            }

            let captured = frames
            do {
                let result = try await BodyMeasurementEngine.measure(frames: captured, subject: subject)
                Haptics.success()
                phase = .finished(result)
            } catch {
                // A failed solve must not cost the user their one scan.
                if didClaimSlot { await BackendClient.shared.releaseBodyScan() }
                Haptics.warning()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        runTask?.cancel()
        runTask = nil
        grabber?.isActive = false
        frames = []
        capturedPoses = []
        progress = 0
        phase = .idle
    }

    func reset() {
        frames = []
        capturedPoses = []
        progress = 0
        phase = .idle
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = CameraDiscovery.bestDevice(position: .back) else {
            access = .noDevice
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            access = .noDevice
            return
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let grabber = FrameGrabber()
        grabber.onBodyVisible = { [weak self] visible in
            Task { @MainActor [weak self] in self?.isBodyVisible = visible }
        }
        self.grabber = grabber
        output.setSampleBufferDelegate(grabber, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Deliver upright buffers so the analysed frames match what the user saw.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()
        isConfigured = true
    }
}

// MARK: - Frame grabbing

/// Runs off the main actor. Keeps the most recent analysis-ready still and
/// whether a full body was visible in it. The lightweight pose pass here is a
/// framing gate; the real measurement happens in `BodyMeasurementEngine`.
private final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var isActive: Bool = false
    var onBodyVisible: (@Sendable (Bool) -> Void)?

    private let lock = NSLock()
    private var latestFullBodyFrame: Data?
    private var latestAnyFrame: Data?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var lastProcessed: CFTimeInterval = 0

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastProcessed > 0.15 else { return }
        lastProcessed = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var hasFullBody = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        if (try? handler.perform([poseRequest])) != nil {
            hasFullBody = Self.isFullBodyVisible(poseRequest.results?.first)
        }
        onBodyVisible?(hasFullBody)

        guard isActive, let jpeg = encode(pixelBuffer) else { return }
        lock.lock()
        latestAnyFrame = jpeg
        if hasFullBody { latestFullBodyFrame = jpeg }
        lock.unlock()
    }

    /// Preferred: the newest frame containing a full body. Falls back to the
    /// newest frame of any kind so a momentary dropout doesn't lose a pose.
    func grab() -> Data? {
        lock.lock()
        defer {
            latestFullBodyFrame = nil
            lock.unlock()
        }
        return latestFullBodyFrame ?? latestAnyFrame
    }

    /// Requires torso and legs to be confidently visible, so partial or
    /// too-close framings are never banked.
    private static func isFullBodyVisible(_ observation: VNHumanBodyPoseObservation?) -> Bool {
        guard let observation else { return false }
        func isPresent(_ joint: VNHumanBodyPoseObservation.JointName) -> Bool {
            guard let point = try? observation.recognizedPoint(joint) else { return false }
            return point.confidence > 0.2
        }
        let hasTorso = (isPresent(.leftShoulder) || isPresent(.rightShoulder))
            && (isPresent(.leftHip) || isPresent(.rightHip))
        let hasLegs = isPresent(.leftKnee) || isPresent(.rightKnee)
            || isPresent(.leftAnkle) || isPresent(.rightAnkle)
        return hasTorso && hasLegs
    }

    private func encode(_ buffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: buffer)
        let longest = max(image.extent.width, image.extent.height)
        // Nothing is uploaded, so the frames stay large and lightly compressed —
        // segmentation edges are what the measurement accuracy rests on.
        let maxDimension: CGFloat = 1440
        if longest > maxDimension {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return ciContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
        )
    }
}
