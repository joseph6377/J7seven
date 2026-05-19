import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    let synthesizer: SupertonicSynthesizer
    var onReady: () -> Void = {}

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("One-Time Setup")
                    .font(.title2.bold())
                Text("Downloading the on-device voice model (~350 MB).\nThis only happens once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            progressSection

            Button("Cancel") { dismiss() }
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
                    .font(.caption)
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
                Text(msg).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { try? await synthesizer.downloadModel() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            ProgressView()
        }
    }
}
