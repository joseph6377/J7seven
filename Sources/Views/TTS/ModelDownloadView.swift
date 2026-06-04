import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    let synthesizer: SupertonicSynthesizer
    var onReady: () -> Void = {}
    var onQuickStart: (() -> Void)? = nil

    @State private var downloadTask: Task<Void, Never>? = nil

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
                    downloadTask?.cancel()
                    downloadTask = nil
                    onQuickStart()
                    dismiss()
                }
                .font(.j7Subheadline)
                .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                downloadTask?.cancel()
                downloadTask = nil
                dismiss()
            }
            .font(.j7Subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(36)
        .onAppear {
            startDownload()
        }
        .onDisappear {
            downloadTask?.cancel()
            downloadTask = nil
        }
    }

    private func startDownload() {
        downloadTask?.cancel()
        downloadTask = Task {
            try? await synthesizer.downloadModel()
            downloadTask = nil
        }
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
                Button("Retry") {
                    startDownload()
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            ProgressView()
        }
    }
}
