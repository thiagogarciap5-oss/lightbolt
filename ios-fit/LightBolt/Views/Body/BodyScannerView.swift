import SwiftUI

/// Guided 360° body scan. Four keyframes are captured as the user turns and
/// measured entirely on this device by `BodyMeasurementEngine` — no upload,
/// no third-party service, no account required.
struct BodyScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = BodyScanSession()
    @State private var ringSpin: Double = 0

    let subject: BodyScanSubject
    let onComplete: (BodyScanResult) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.access == .authorized {
                CameraPreviewView(session: session.session)
                    .ignoresSafeArea()
                    .overlay(overlay)
            } else {
                unavailable
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                dock
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await session.prepare()
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { ringSpin = 360 }
        }
        .onDisappear { session.teardown() }
    }

    // MARK: Overlay

    private var overlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Standing guide silhouette frame
            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .strokeBorder(
                    session.isBodyVisible ? LightBoltTheme.volt.opacity(0.9) : LightBoltTheme.inkFaint.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                )
                .padding(.horizontal, 78)
                .padding(.vertical, 96)
                .animation(.easeInOut(duration: 0.3), value: session.isBodyVisible)

            if session.phase == .capturing {
                rotationGuide
            }

            if case .countdown(let value) = session.phase {
                Text("\(value)")
                    .font(.fitNumeric(150, weight: .black))
                    .voltWash()
                    .transition(.scale.combined(with: .opacity))
                    .id(value)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var rotationGuide: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .stroke(LightBoltTheme.charcoal.opacity(0.7), lineWidth: 6)
                    .frame(width: 108, height: 108)
                Circle()
                    .trim(from: 0, to: session.progress)
                    .stroke(LightBoltTheme.volt, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LightBoltTheme.volt)
                    .rotationEffect(.degrees(ringSpin))
            }
            Spacer()
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tick()
                session.cancelScan()
                session.teardown()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(session.isBodyVisible ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                    .frame(width: 7, height: 7)
                EyebrowText(
                    text: session.isBodyVisible ? "Full body in frame" : "Step back into frame",
                    color: session.isBodyVisible ? LightBoltTheme.volt : LightBoltTheme.inkMuted
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.55)))

            Spacer()

            Image(systemName: "iphone.gen3")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LightBoltTheme.volt)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(0.55)))
                .accessibilityLabel("Measured on this device. No frames are uploaded.")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder private var dock: some View {
        switch session.phase {
        case .idle:
            VStack(spacing: 18) {
                instructionCard
                VoltButton(title: "Begin Scan", systemImage: "figure.stand") {
                    Haptics.thud()
                    session.beginScan(subject: subject)
                }
                .disabled(session.access != .authorized)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)

        case .countdown:
            VStack(spacing: 10) {
                EyebrowText(text: "Get into position", color: LightBoltTheme.volt)
                Text("Full body inside the frame, arms slightly away from your sides.")
                    .font(.fitBody(13))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 46)

        case .capturing:
            VStack(spacing: 14) {
                Text("TURN LEFT")
                    .font(.fitDisplay(38))
                    .tracking(-0.5)
                    .voltWash()
                Text("Keep turning slowly until the ring closes.")
                    .font(.fitBody(13))
                    .foregroundStyle(.white.opacity(0.85))

                poseChecklist

                Button {
                    Haptics.tick()
                    session.cancelScan()
                } label: {
                    Text("CANCEL")
                        .font(.fitLabel(11))
                        .tracking(1.6)
                        .foregroundStyle(LightBoltTheme.inkMuted)
                }
                .buttonStyle(VoltPressStyle())
            }
            .padding(.bottom, 38)

        case .analyzing:
            VStack(spacing: 14) {
                RunningWaveLoader(barCount: 7, height: 26)
                EyebrowText(text: "Measuring on this device", color: LightBoltTheme.volt)
                Text("Solving circumferences from \(session.capturedPoses.count) angles — nothing leaves your phone.")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 52)

        case .finished(let result):
            resultCard(result)

        case .failed(let message):
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LightBoltTheme.alert)
                    Text(message)
                        .font(.fitBody(13))
                        .foregroundStyle(LightBoltTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fitCard(radius: 16, stroke: LightBoltTheme.alert.opacity(0.4), fill: LightBoltTheme.obsidian)

                VoltButton(title: "Scan Again", systemImage: "arrow.clockwise") {
                    session.reset()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
    }

    /// Live tick-list of the four angles as they're banked during the turn.
    private var poseChecklist: some View {
        HStack(spacing: 8) {
            ForEach(ScanPose.allCases, id: \.rawValue) { pose in
                let captured = session.capturedPoses.contains(pose)
                HStack(spacing: 5) {
                    Image(systemName: captured ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 11, weight: .bold))
                    Text(pose.label.uppercased())
                        .font(.fitLabel(9))
                        .tracking(1)
                }
                .foregroundStyle(captured ? .black : LightBoltTheme.inkMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(captured ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh.opacity(0.8))
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: captured)
            }
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: "Before you start", color: LightBoltTheme.voltDim)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.fitNumeric(12))
                        .foregroundStyle(.black)
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(LightBoltTheme.volt))
                    Text(step)
                        .font(.fitBody(13))
                        .foregroundStyle(LightBoltTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(fill: LightBoltTheme.obsidian)
    }

    private let steps = [
        "Stand your phone upright 2–3 m away, camera at hip height.",
        "Wear fitted clothing against a plain background.",
        "Start facing the camera, then turn slowly to your left through a full circle.",
        "Everything is measured on your device — no photo is ever uploaded."
    ]

    private func resultCard(_ result: BodyScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: "Scan complete", color: LightBoltTheme.voltDim)
                    Text("MEASURED")
                        .font(.fitDisplay(34))
                        .foregroundStyle(LightBoltTheme.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(result.confidence * 100))%")
                        .font(.fitNumeric(26))
                        .voltWash()
                    EyebrowText(text: "confidence", color: LightBoltTheme.inkFaint)
                }
            }

            // The three headline circumferences the provider returns.
            HStack(spacing: 8) {
                metric("Waist", result.waistCm)
                metric("Hips", result.hipCm)
                metric("Chest", result.chestCm)
            }

            if result.shoulderCm > 0 || result.thighCm > 0 || result.bodyFatPercent != nil {
                HStack(spacing: 8) {
                    if result.shoulderCm > 0 { metric("Shoulders", result.shoulderCm) }
                    if result.thighCm > 0 { metric("Thigh", result.thighCm) }
                    if let fat = result.bodyFatPercent { metric("Body fat", fat, unit: "%") }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tick()
                    session.reset()
                } label: {
                    Text("REDO")
                        .font(.fitTitle(15))
                        .tracking(1.4)
                        .foregroundStyle(LightBoltTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LightBoltTheme.charcoalHigh))
                }
                .buttonStyle(VoltPressStyle())

                Button {
                    Haptics.success()
                    onComplete(result)
                    session.teardown()
                    dismiss()
                } label: {
                    Text("SAVE SCAN")
                        .font(.fitTitle(15))
                        .tracking(1.4)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LightBoltTheme.volt))
                }
                .buttonStyle(VoltPressStyle())
            }
        }
        .padding(18)
        .fitCard(fill: LightBoltTheme.obsidian)
        .padding(.horizontal, 14)
        .padding(.bottom, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func metric(_ label: String, _ value: Double, unit: String = "cm") -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%.1f", value))
                .font(.fitNumeric(20))
                .foregroundStyle(LightBoltTheme.ink)
            EyebrowText(text: "\(label) \(unit)", color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(LightBoltTheme.charcoalHigh))
    }

    private var unavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: session.access == .denied ? "lock.slash.fill" : "video.slash.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LightBoltTheme.voltDim)
            Text(session.access == .denied ? "CAMERA ACCESS OFF" : "NO CAMERA FOUND")
                .font(.fitTitle(20))
                .tracking(1.2)
                .foregroundStyle(LightBoltTheme.ink)
            Text(session.access == .denied
                 ? "Body scanning needs the camera. Enable it for LightBolt in iOS Settings."
                 : "Connect or enable a camera to run a body scan.")
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if session.access == .denied {
                Button {
                    Haptics.tap()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("OPEN SETTINGS")
                        .font(.fitLabel(11))
                        .tracking(1.4)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(LightBoltTheme.volt))
                }
                .buttonStyle(VoltPressStyle())
            }
        }
    }
}
