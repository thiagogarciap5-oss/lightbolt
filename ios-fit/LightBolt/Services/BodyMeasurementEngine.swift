import CoreGraphics
import CoreVideo
import Foundation
import UIKit
import Vision

/// One keyframe banked during the 360° turn, kept as an encoded still so it can
/// cross to a background task safely.
nonisolated struct CapturedFrame: Sendable {
    let pose: ScanPose
    let jpeg: Data
}

nonisolated enum BodyMeasurementError: LocalizedError, Sendable {
    case unreadableFrames
    case bodyNotFound
    case implausibleResult

    var errorDescription: String? {
        switch self {
        case .unreadableFrames:
            "LightBolt couldn't read the captured frames. Run the scan again."
        case .bodyNotFound:
            "LightBolt couldn't isolate your full body. Stand 2–3 m back against a plain wall so your head and feet are both inside the frame, arms slightly away from your sides."
        case .implausibleResult:
            "The measurements didn't resolve cleanly. Wear fitted clothing, keep your whole body in frame, and scan again."
        }
    }
}

/// **On-device body measurement.** Everything in this file runs locally on the
/// user's chip with AVFoundation frames and Apple's Vision framework. No frame,
/// photo or measurement is ever uploaded, and there is no third-party scanning
/// service involved.
///
/// Pipeline, per captured frame:
/// 1. `VNGeneratePersonSegmentationRequest` isolates the body silhouette mask.
/// 2. `VNDetectHumanBodyPoseRequest` locates shoulders, hips, knees and ankles,
///    so anatomical rows are found from the user's own proportions rather than
///    from fixed fractions of the image.
/// 3. The silhouette's standing pixel height is divided by the user's real
///    height to derive a pixels-per-centimetre scale for that specific frame.
///    This is the spatial pixel-ratio estimation the whole solve rests on.
/// 4. Front and back frames give body **widths** at the neck, chest, waist, hip
///    and thigh rows; the two side frames give body **depths** at the same rows.
/// 5. Each circumference is solved as an ellipse from its width and depth using
///    Ramanujan's perimeter approximation, then nudged by a small empirical
///    shape factor because a human cross-section isn't a perfect ellipse.
///
/// Results are approximations for tracking *change over time*. They are not
/// medical measurements, and the UI presents them with a confidence score.
nonisolated enum BodyMeasurementEngine {

    // MARK: Tuning constants

    /// Where each landmark sits as a fraction of the shoulder→hip torso span.
    private enum Row {
        static let chestSearch: ClosedRange<Double> = 0.10...0.34
        static let waistSearch: ClosedRange<Double> = 0.44...0.86
        static let hipSearch: ClosedRange<Double> = -0.06...0.26
        /// Thigh row as a fraction of the hip→knee span.
        static let thigh: Double = 0.34
    }

    /// A real torso is flatter at the front than a true ellipse, so the ellipse
    /// perimeter is corrected by these empirically-derived factors.
    private enum ShapeFactor {
        static let chest: Double = 1.025
        static let waist: Double = 1.010
        static let hip: Double = 1.005
        static let neck: Double = 1.0
        static let thigh: Double = 1.0
    }

    /// Used only when no clean side profile was captured: typical depth-to-width
    /// ratios for a standing adult, so a front-only scan still returns a figure.
    private enum FallbackDepthRatio {
        static let chest: Double = 0.72
        static let waist: Double = 0.76
        static let hip: Double = 0.70
        static let neck: Double = 1.0
    }

    private static let plausibleChest: ClosedRange<Double> = 50...200
    private static let plausibleWaist: ClosedRange<Double> = 40...200
    private static let plausibleHip: ClosedRange<Double> = 50...200

    // MARK: Entry point

    /// Solves the captured turn into real-world centimetres.
    ///
    /// Declared `nonisolated async`, so it executes off the main actor and the
    /// scanning UI keeps animating while the chip works.
    static func measure(frames: [CapturedFrame], subject: BodyScanSubject) async throws -> BodyScanResult {
        guard !frames.isEmpty else { throw BodyMeasurementError.unreadableFrames }

        var widthProfiles: [TorsoProfile] = []
        var depthProfiles: [DepthProfile] = []
        var landmarkConfidences: [Double] = []
        var analysedFrames = 0

        for frame in frames {
            guard let geometry = try? analyse(frame: frame, subject: subject) else { continue }
            analysedFrames += 1
            landmarkConfidences.append(geometry.landmarks.confidence)

            switch frame.pose {
            case .front, .back:
                if let profile = torsoProfile(from: geometry) { widthProfiles.append(profile) }
            case .right, .left:
                if let profile = depthProfile(from: geometry) { depthProfiles.append(profile) }
            }
        }

        guard let widths = TorsoProfile.average(widthProfiles) else {
            throw analysedFrames == 0 ? BodyMeasurementError.unreadableFrames : BodyMeasurementError.bodyNotFound
        }

        // A side profile is a bonus, not a requirement — a front-only scan still
        // resolves using anthropometric depth ratios, at a lower confidence.
        let depths = DepthProfile.average(depthProfiles).flatMap { validated($0, against: widths) }

        let chest = circumference(
            width: widths.chest,
            depth: depths?.chest ?? widths.chest * FallbackDepthRatio.chest,
            factor: ShapeFactor.chest
        )
        let waist = circumference(
            width: widths.waist,
            depth: depths?.waist ?? widths.waist * FallbackDepthRatio.waist,
            factor: ShapeFactor.waist
        )
        let hip = circumference(
            width: widths.hip,
            depth: depths?.hip ?? widths.hip * FallbackDepthRatio.hip,
            factor: ShapeFactor.hip
        )
        let neck = widths.neck > 0
            ? circumference(
                width: widths.neck,
                depth: depths?.neck ?? widths.neck * FallbackDepthRatio.neck,
                factor: ShapeFactor.neck
            )
            : 0
        // Limbs are close enough to circular that a single width carries them.
        let thigh = widths.thigh > 0 ? .pi * widths.thigh * ShapeFactor.thigh : 0

        guard plausibleChest.contains(chest),
              plausibleWaist.contains(waist),
              plausibleHip.contains(hip) else {
            throw BodyMeasurementError.implausibleResult
        }

        let averageLandmarkConfidence = landmarkConfidences.isEmpty
            ? 0
            : landmarkConfidences.reduce(0, +) / Double(landmarkConfidences.count)

        return BodyScanResult(
            chestCm: round(chest * 10) / 10,
            waistCm: round(waist * 10) / 10,
            hipCm: round(hip * 10) / 10,
            shoulderCm: round(widths.shoulderBreadth * 10) / 10,
            thighCm: round(thigh * 10) / 10,
            bodyFatPercent: navyBodyFat(waistCm: waist, hipCm: hip, neckCm: neck, subject: subject),
            confidence: confidence(
                landmarkConfidence: averageLandmarkConfidence,
                widthFrames: widthProfiles.count,
                hasDepth: depths != nil
            ),
            provider: "On-device Vision",
            frameCount: analysedFrames
        )
    }

    // MARK: Per-frame geometry

    private struct FrameGeometry {
        let silhouette: Silhouette
        let landmarks: Landmarks
        /// Spatial pixel ratio: silhouette pixels per real-world centimetre.
        let pixelsPerCm: Double
    }

    private static func analyse(frame: CapturedFrame, subject: BodyScanSubject) throws -> FrameGeometry {
        guard let image = UIImage(data: frame.jpeg)?.cgImage else {
            throw BodyMeasurementError.unreadableFrames
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])

        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let pose = VNDetectHumanBodyPoseRequest()

        try handler.perform([segmentation, pose])

        guard let maskBuffer = (segmentation.results?.first)?.pixelBuffer,
              let silhouette = Silhouette(mask: maskBuffer) else {
            throw BodyMeasurementError.bodyNotFound
        }

        // Scale is only trustworthy when the whole standing body is inside the
        // frame — a cropped head or feet would silently inflate every result.
        guard silhouette.top > 1,
              silhouette.bottom < silhouette.height - 2,
              silhouette.pixelHeight > Double(silhouette.height) * 0.35 else {
            throw BodyMeasurementError.bodyNotFound
        }

        guard let observation = pose.results?.first,
              let landmarks = Landmarks(observation: observation, silhouette: silhouette) else {
            throw BodyMeasurementError.bodyNotFound
        }

        return FrameGeometry(
            silhouette: silhouette,
            landmarks: landmarks,
            pixelsPerCm: silhouette.pixelHeight / subject.heightCm
        )
    }

    // MARK: Profiles

    /// Body widths in centimetres, read from a front or back frame.
    private struct TorsoProfile {
        let neck: Double
        let chest: Double
        let waist: Double
        let hip: Double
        let thigh: Double
        let shoulderBreadth: Double

        static func average(_ profiles: [TorsoProfile]) -> TorsoProfile? {
            guard !profiles.isEmpty else { return nil }
            func mean(_ keyPath: KeyPath<TorsoProfile, Double>) -> Double {
                // Zero means "not measurable in this frame" — never average it in.
                let values = profiles.map { $0[keyPath: keyPath] }.filter { $0 > 0 }
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / Double(values.count)
            }
            let merged = TorsoProfile(
                neck: mean(\.neck),
                chest: mean(\.chest),
                waist: mean(\.waist),
                hip: mean(\.hip),
                thigh: mean(\.thigh),
                shoulderBreadth: mean(\.shoulderBreadth)
            )
            guard merged.chest > 0, merged.waist > 0, merged.hip > 0 else { return nil }
            return merged
        }
    }

    /// Front-to-back body depths in centimetres, read from a side frame.
    private struct DepthProfile {
        let neck: Double
        let chest: Double
        let waist: Double
        let hip: Double

        static func average(_ profiles: [DepthProfile]) -> DepthProfile? {
            guard !profiles.isEmpty else { return nil }
            func mean(_ keyPath: KeyPath<DepthProfile, Double>) -> Double {
                let values = profiles.map { $0[keyPath: keyPath] }.filter { $0 > 0 }
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / Double(values.count)
            }
            let merged = DepthProfile(
                neck: mean(\.neck),
                chest: mean(\.chest),
                waist: mean(\.waist),
                hip: mean(\.hip)
            )
            guard merged.chest > 0, merged.waist > 0, merged.hip > 0 else { return nil }
            return merged
        }
    }

    private static func torsoProfile(from geometry: FrameGeometry) -> TorsoProfile? {
        let silhouette = geometry.silhouette
        let marks = geometry.landmarks
        let torso = marks.hipY - marks.shoulderY
        guard torso > 8 else { return nil }

        let scale = geometry.pixelsPerCm
        guard scale > 0.2 else { return nil }

        // Chest: the widest row just under the shoulders.
        let chestPx = silhouette.maxWidth(
            from: marks.shoulderY + torso * Row.chestSearch.lowerBound,
            to: marks.shoulderY + torso * Row.chestSearch.upperBound
        )
        // Natural waist: the narrowest row between ribcage and hips.
        let waistPx = silhouette.minWidth(
            from: marks.shoulderY + torso * Row.waistSearch.lowerBound,
            to: marks.shoulderY + torso * Row.waistSearch.upperBound
        )
        // Hips: the widest row across the seat.
        let hipPx = silhouette.maxWidth(
            from: marks.hipY + torso * Row.hipSearch.lowerBound,
            to: marks.hipY + torso * Row.hipSearch.upperBound
        )
        // Neck: the narrowest row between the head and the shoulder line.
        let neckPx = marks.headY < marks.shoulderY
            ? silhouette.minWidth(from: marks.headY + (marks.shoulderY - marks.headY) * 0.35, to: marks.shoulderY - torso * 0.04)
            : 0

        guard chestPx > 0, waistPx > 0, hipPx > 0 else { return nil }

        return TorsoProfile(
            neck: neckPx / scale,
            chest: chestPx / scale,
            waist: waistPx / scale,
            hip: hipPx / scale,
            thigh: thighWidth(silhouette: silhouette, marks: marks) / scale,
            shoulderBreadth: marks.shoulderSpanPx / scale
        )
    }

    private static func depthProfile(from geometry: FrameGeometry) -> DepthProfile? {
        let silhouette = geometry.silhouette
        let marks = geometry.landmarks
        let torso = marks.hipY - marks.shoulderY
        guard torso > 8 else { return nil }

        let scale = geometry.pixelsPerCm
        guard scale > 0.2 else { return nil }

        // Depth is read at the same anatomical rows, resolved from this frame's
        // own landmarks so a different distance-to-camera can't skew it.
        let chestPx = silhouette.stableWidth(atRow: marks.shoulderY + torso * 0.22)
        let waistPx = silhouette.stableWidth(atRow: marks.shoulderY + torso * 0.68)
        let hipPx = silhouette.stableWidth(atRow: marks.hipY + torso * 0.08)
        let neckPx = marks.headY < marks.shoulderY
            ? silhouette.stableWidth(atRow: marks.shoulderY - torso * 0.10)
            : 0

        guard chestPx > 0, waistPx > 0, hipPx > 0 else { return nil }

        return DepthProfile(
            neck: neckPx / scale,
            chest: chestPx / scale,
            waist: waistPx / scale,
            hip: hipPx / scale
        )
    }

    /// Rejects a "side" frame the user didn't actually turn for. Without this a
    /// second front-facing frame would be read as depth and balloon every girth.
    private static func validated(_ depths: DepthProfile, against widths: TorsoProfile) -> DepthProfile? {
        let ratios = [
            depths.chest / max(widths.chest, 0.001),
            depths.waist / max(widths.waist, 0.001),
            depths.hip / max(widths.hip, 0.001)
        ]
        return ratios.allSatisfy { $0 >= 0.35 && $0 <= 1.25 } ? depths : nil
    }

    private static func thighWidth(silhouette: Silhouette, marks: Landmarks) -> Double {
        guard marks.kneeY > marks.hipY else { return 0 }
        let row = marks.hipY + (marks.kneeY - marks.hipY) * Row.thigh
        let runs = silhouette.runs(atRow: Int(row.rounded()))
        guard let widest = runs.map(\.count).max(), widest > 0 else { return 0 }
        // Two runs means the legs are separated and the widest run is one thigh;
        // a single run means they're touching, so it spans both.
        return runs.count >= 2 ? Double(widest) : Double(widest) / 2
    }

    // MARK: Maths

    /// Ramanujan's approximation of an ellipse perimeter, with a shape correction.
    private static func circumference(width: Double, depth: Double, factor: Double) -> Double {
        guard width > 0, depth > 0 else { return 0 }
        let a = width / 2
        let b = depth / 2
        let perimeter = Double.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
        return perimeter * factor
    }

    /// US Navy body-fat estimate, derived from the circumferences we just
    /// measured. Returns nil rather than an implausible figure.
    private static func navyBodyFat(
        waistCm: Double,
        hipCm: Double,
        neckCm: Double,
        subject: BodyScanSubject
    ) -> Double? {
        guard neckCm > 20, waistCm > neckCm, subject.heightCm > 80 else { return nil }

        let height = log10(subject.heightCm)
        let percent: Double
        if subject.isFemale {
            let girth = waistCm + hipCm - neckCm
            guard girth > 0 else { return nil }
            percent = 495 / (1.29579 - 0.35004 * log10(girth) + 0.22100 * height) - 450
        } else {
            percent = 495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * height) - 450
        }

        guard percent.isFinite, percent > 3, percent < 65 else { return nil }
        return round(percent * 10) / 10
    }

    /// Honest confidence: highest with a validated side profile and strong joints.
    private static func confidence(landmarkConfidence: Double, widthFrames: Int, hasDepth: Bool) -> Double {
        var score = 0.52
        if hasDepth { score += 0.18 }
        if widthFrames > 1 { score += 0.08 }
        score += 0.18 * min(1, max(0, landmarkConfidence))
        return min(0.93, max(0.4, round(score * 100) / 100))
    }
}

// MARK: - Silhouette

/// A thresholded person-segmentation mask, addressable row by row.
private struct Silhouette {
    let width: Int
    let height: Int
    let top: Int
    let bottom: Int

    private let pixels: [UInt8]
    private let minimumRun: Int

    var pixelHeight: Double { Double(bottom - top) }

    init?(mask: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard width > 16, height > 16,
              let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let source = base.assumingMemoryBound(to: UInt8.self)

        // Copy into a tightly-packed buffer so row maths stays simple.
        var packed = [UInt8](repeating: 0, count: width * height)
        packed.withUnsafeMutableBufferPointer { destination in
            guard let out = destination.baseAddress else { return }
            for row in 0..<height {
                (out + row * width).update(from: source + row * bytesPerRow, count: width)
            }
        }

        self.width = width
        self.height = height
        self.pixels = packed
        self.minimumRun = max(2, width / 110)

        // Vertical extent of the body, ignoring rows that are only speckle.
        let threshold = max(3, width / 90)
        var first = -1
        var last = -1
        for row in 0..<height {
            var count = 0
            let base = row * width
            for column in 0..<width where packed[base + column] > 128 {
                count += 1
                if count >= threshold { break }
            }
            if count >= threshold {
                if first < 0 { first = row }
                last = row
            }
        }
        guard first >= 0, last > first else { return nil }
        self.top = first
        self.bottom = last
    }

    /// Contiguous horizontal runs of body pixels on one row, speckle removed.
    func runs(atRow y: Int) -> [Range<Int>] {
        guard y >= 0, y < height else { return [] }
        var result: [Range<Int>] = []
        var start: Int?
        let base = y * width

        for x in 0..<width {
            let isBody = pixels[base + x] > 128
            if isBody, start == nil { start = x }
            if !isBody, let s = start {
                if x - s >= minimumRun { result.append(s..<x) }
                start = nil
            }
        }
        if let s = start, width - s >= minimumRun { result.append(s..<width) }
        return result
    }

    /// Widest run on a row — the torso, with arms held away read as separate runs.
    private func torsoWidth(atRow y: Int) -> Int {
        runs(atRow: y).map(\.count).max() ?? 0
    }

    /// Median torso width across a small band of rows, to resist mask noise.
    func stableWidth(atRow y: Double, span: Int = 3) -> Double {
        let centre = Int(y.rounded())
        var samples: [Int] = []
        for offset in -span...span {
            let row = centre + offset
            guard row >= 0, row < height else { continue }
            let value = torsoWidth(atRow: row)
            if value > 0 { samples.append(value) }
        }
        guard !samples.isEmpty else { return 0 }
        samples.sort()
        return Double(samples[samples.count / 2])
    }

    func minWidth(from y0: Double, to y1: Double) -> Double {
        scan(from: y0, to: y1) { $0 < $1 }
    }

    func maxWidth(from y0: Double, to y1: Double) -> Double {
        scan(from: y0, to: y1) { $0 > $1 }
    }

    private func scan(from y0: Double, to y1: Double, _ isBetter: (Double, Double) -> Bool) -> Double {
        let lower = max(0, Int(min(y0, y1).rounded()))
        let upper = min(height - 1, Int(max(y0, y1).rounded()))
        guard lower < upper else { return 0 }

        var best: Double = 0
        for row in stride(from: lower, through: upper, by: 1) {
            let value = stableWidth(atRow: Double(row), span: 2)
            guard value > 0 else { continue }
            if best == 0 || isBetter(value, best) { best = value }
        }
        return best
    }
}

// MARK: - Landmarks

/// Body-pose joints projected into silhouette pixel space.
private struct Landmarks {
    let headY: Double
    let shoulderY: Double
    let hipY: Double
    let kneeY: Double
    let shoulderSpanPx: Double
    let confidence: Double

    init?(observation: VNHumanBodyPoseObservation, silhouette: Silhouette) {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            guard let value = try? observation.recognizedPoint(joint), value.confidence > 0.15 else { return nil }
            return value
        }
        /// Vision's origin is bottom-left; the silhouette is addressed top-down.
        func row(_ value: VNRecognizedPoint) -> Double {
            (1 - value.location.y) * Double(silhouette.height)
        }
        func column(_ value: VNRecognizedPoint) -> Double {
            value.location.x * Double(silhouette.width)
        }
        func midRow(_ a: VNRecognizedPoint?, _ b: VNRecognizedPoint?) -> Double? {
            switch (a, b) {
            case let (lhs?, rhs?): (row(lhs) + row(rhs)) / 2
            case let (lhs?, nil): row(lhs)
            case let (nil, rhs?): row(rhs)
            default: nil
            }
        }

        let leftShoulder = point(.leftShoulder)
        let rightShoulder = point(.rightShoulder)
        let leftHip = point(.leftHip)
        let rightHip = point(.rightHip)

        guard let shoulderRow = midRow(leftShoulder, rightShoulder),
              let hipRow = midRow(leftHip, rightHip),
              hipRow > shoulderRow else { return nil }

        // Legs must be present, otherwise the standing height used for scale
        // isn't the user's real height.
        guard point(.leftAnkle) != nil || point(.rightAnkle) != nil else { return nil }

        self.shoulderY = shoulderRow
        self.hipY = hipRow
        self.kneeY = midRow(point(.leftKnee), point(.rightKnee)) ?? hipRow + (hipRow - shoulderRow)
        self.headY = point(.nose).map(row) ?? Double(silhouette.top)

        // Shoulder breadth only makes sense when both shoulders are resolved,
        // which is exactly the front/back frames.
        if let left = leftShoulder, let right = rightShoulder {
            self.shoulderSpanPx = abs(column(left) - column(right))
        } else {
            self.shoulderSpanPx = 0
        }

        let confidences = [leftShoulder, rightShoulder, leftHip, rightHip]
            .compactMap { $0 }
            .map { Double($0.confidence) }
        self.confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    }
}
