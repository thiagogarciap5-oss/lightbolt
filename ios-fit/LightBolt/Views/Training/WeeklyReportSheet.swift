import PDFKit
import SwiftUI

/// A generated report ready to preview and share.
struct ReportDocument: Identifiable {
    let url: URL
    let sessions: Int
    let scans: Int

    var id: String { url.absoluteString }
}

/// Preview + share surface for the exported weekly PDF.
struct WeeklyReportSheet: View {
    let document: ReportDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(spacing: 0) {
                header

                PDFPreview(url: document.url)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                dock
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(text: "\(document.sessions) sessions · \(document.scans) scans", color: LightBoltTheme.voltDim)
                Text("WEEKLY REPORT")
                    .font(.fitDisplay(36))
                    .tracking(-1.2)
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Button {
                Haptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(LightBoltTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LightBoltTheme.charcoal))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .accessibilityLabel("Close report")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var dock: some View {
        VStack(spacing: 10) {
            ShareLink(item: document.url) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                    Text("SHARE PDF")
                        .font(.fitTitle(17))
                        .tracking(1.6)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightBoltTheme.volt)
                )
            }
            .buttonStyle(VoltPressStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })

            Text("Save it to Files, mail it to a coach, or print it.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }
}

/// Thin PDFKit wrapper — real vector preview of the exact file being shared.
private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
