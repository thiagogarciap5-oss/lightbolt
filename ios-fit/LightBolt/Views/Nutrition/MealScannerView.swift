import SwiftUI

/// Full-screen plate scanner: live camera, capture, server analysis, review.
struct MealScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = MealCamera()
    @State private var stage: Stage = .framing
    @State private var capturedThumbnail: Data?
    @State private var note: String = ""
    @State private var scanLine: CGFloat = -0.5

    let onConfirm: (MealAnalysisDTO, Data?) -> Void

    private enum Stage: Equatable {
        case framing
        case analysing
        case review(MealAnalysisDTO)
        case failed(String)

        static func == (lhs: Stage, rhs: Stage) -> Bool {
            switch (lhs, rhs) {
            case (.framing, .framing), (.analysing, .analysing): true
            case (.review, .review): true
            case let (.failed(a), .failed(b)): a == b
            default: false
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.access == .authorized {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(scrim)
            } else {
                cameraUnavailable
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                content
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await camera.start()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { scanLine = 0.5 }
        }
        .onDisappear { camera.stop() }
    }

    // MARK: Chrome

    private var scrim: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.15), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            if stage == .framing {
                reticle
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var reticle: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 56, 320)
            ZStack {
                ForEach(0..<4, id: \.self) { corner in
                    CornerBracket()
                        .stroke(LightBoltTheme.volt, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(Double(corner) * 90))
                        .offset(
                            x: (corner == 0 || corner == 3 ? -1 : 1) * (side / 2 - 15),
                            y: (corner < 2 ? -1 : 1) * (side / 2 - 15)
                        )
                }
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, LightBoltTheme.volt.opacity(0.85), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: side, height: 2)
                    .offset(y: scanLine * side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tick()
                camera.stop()
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

            EyebrowText(text: stageLabel, color: LightBoltTheme.volt)

            Spacer()

            Button {
                Haptics.tick()
                camera.toggleTorch()
            } label: {
                Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(camera.isTorchOn ? .black : .white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(camera.isTorchOn ? LightBoltTheme.volt : .black.opacity(0.55)))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .opacity(camera.access == .authorized ? 1 : 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var stageLabel: String {
        switch stage {
        case .framing: "Frame the plate"
        case .analysing: "Analysing"
        case .review: "Review"
        case .failed: "Retry"
        }
    }

    // MARK: Stages

    @ViewBuilder private var content: some View {
        switch stage {
        case .framing:
            framingControls
        case .analysing:
            VStack(spacing: 16) {
                MealAnalysisSkeleton()
                EyebrowText(text: "Estimating calories and macros", color: LightBoltTheme.inkFaint)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
            .transition(.move(edge: .bottom).combined(with: .opacity))

        case .review(let analysis):
            reviewCard(analysis)
                .transition(.move(edge: .bottom).combined(with: .opacity))

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
                .fitCard(radius: 16, stroke: LightBoltTheme.alert.opacity(0.4))

                VoltButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { stage = .framing }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
    }

    private var framingControls: some View {
        VStack(spacing: 20) {
            Text("Fill the frame with your plate. Shoot from above at a slight angle for the best estimate.")
                .font(.fitBody(13))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                capture()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(LightBoltTheme.volt, lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .fill(LightBoltTheme.volt)
                        .frame(width: 68, height: 68)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .disabled(camera.access != .authorized)
            .opacity(camera.access == .authorized ? 1 : 0.35)
        }
        .padding(.bottom, 40)
    }

    private func reviewCard(_ analysis: MealAnalysisDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText(text: "Identified", color: LightBoltTheme.voltDim)
                    Text(analysis.mealName)
                        .font(.fitTitle(24))
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(analysis.calories)")
                        .font(.fitNumeric(38))
                        .voltWash()
                    EyebrowText(text: "kcal", color: LightBoltTheme.inkFaint)
                }
            }

            HStack(spacing: 10) {
                macroBox("Protein", analysis.protein)
                macroBox("Carbs", analysis.carbs)
                macroBox("Fat", analysis.fat)
            }

            if !analysis.items.isEmpty {
                Text(analysis.items.joined(separator: " · "))
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11, weight: .bold))
                Text("~\(Int(analysis.estimatedGrams)) g · \(Int(analysis.confidence * 100))% confidence")
                    .font(.fitLabel(10))
                    .tracking(0.8)
            }
            .foregroundStyle(LightBoltTheme.inkFaint)

            HStack(spacing: 10) {
                Button {
                    Haptics.tick()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { stage = .framing }
                } label: {
                    Text("RESCAN")
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
                    onConfirm(analysis, capturedThumbnail)
                    camera.stop()
                    dismiss()
                } label: {
                    Text("LOG MEAL")
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
        .padding(.bottom, 30)
    }

    private func macroBox(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(value))g")
                .font(.fitNumeric(19))
                .foregroundStyle(LightBoltTheme.ink)
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LightBoltTheme.charcoalHigh))
    }

    private var cameraUnavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: camera.access == .denied ? "lock.slash.fill" : "video.slash.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LightBoltTheme.voltDim)
            Text(camera.access == .denied ? "CAMERA ACCESS OFF" : "NO CAMERA FOUND")
                .font(.fitTitle(20))
                .tracking(1.2)
                .foregroundStyle(LightBoltTheme.ink)
            Text(camera.access == .denied
                 ? "Enable camera access for LightBolt in iOS Settings to scan meals."
                 : "Connect or enable a camera to use plate scanning.")
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if camera.access == .denied {
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

    // MARK: Actions

    private func capture() {
        Haptics.thud()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { stage = .analysing }

        Task { @MainActor in
            guard let data = await camera.capturePhoto() else {
                withAnimation { stage = .failed("The camera didn't return an image. Try again.") }
                Haptics.failure()
                return
            }
            capturedThumbnail = ImageDownscaler.thumbnail(from: data)

            do {
                let analysis = try await BackendClient.shared.analyzeMeal(imageData: data, note: note)
                Haptics.success()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { stage = .review(analysis) }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Analysis failed. Try again."
                Haptics.failure()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { stage = .failed(message) }
            }
        }
    }
}

/// One L-shaped bracket of the capture reticle.
struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
