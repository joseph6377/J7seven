import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    let synthesizer: SupertonicSynthesizer
    var onReady: () -> Void = {}
    var onQuickStart: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "arrow.down.circle")
                .font(.j7Hero)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("One-Time Setup")
                    .font(.j7Title2)
                Text("Downloading the on-device voice model (~350 MB).\nThis only happens once.")
                    .font(.j7Subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            progressSection

            if let onQuickStart {
                Button("Quick Start with Apple Voice") {
                    onQuickStart()
                    dismiss()
                }
                .font(.j7Subheadline)
                .foregroundStyle(.secondary)
            }

            Button("Cancel") { dismiss() }
                .font(.j7Subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .task { try? await synthesizer.downloadModel() }
    }

    @ViewBuilder
    private var progressSection: some View {
        switch synthesizer.modelState {
        case .downloading(let p):
            VStack(spacing: 8) {
                ProgressView(value: p)
                    .tint(.accentColor)
                    .frame(maxWidth: 280)
                Text("\(Int(p * 100))%")
                    .font(.j7Caption)
                    .foregroundStyle(.secondary)
            }
        case .loading:
            ProgressView("Loading model…")
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .onAppear {
                    onReady()
                    dismiss()
                }
        case .error(let msg):
            VStack(spacing: 12) {
                Label("Download failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(msg).font(.j7Caption).foregroundStyle(.secondary)
                Button("Retry") { Task { try? await synthesizer.downloadModel() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            ProgressView()
        }
    }
}
