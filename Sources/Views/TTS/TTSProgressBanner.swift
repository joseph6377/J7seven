import SwiftUI

/// Persistent banner shown at the bottom of the library while generation is active.
struct TTSProgressBanner: View {
    let service: TTSGenerationService
    var onListenNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Animated waveform icon
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText).font(.subheadline.bold()).lineLimit(1)
                if let sub = subtitleText {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            // Listen Now
            if service.canPlayNow {
                Button(action: onListenNow) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            }

            // Pause / Resume
            switch service.state {
            case .generating:
                Button { service.pause() } label: {
                    Image(systemName: "pause.fill").font(.title3)
                }
            case .paused:
                Button { service.resume() } label: {
                    Image(systemName: "play.fill").font(.title3)
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    private var titleText: String {
        switch service.state {
        case .preparingModel:               return "Preparing voice model…"
        case .generating:                   return "Generating audiobook…"
        case .paused:                       return "Generation paused"
        case .finalizingAudio:              return "Finalizing audio…"
        case .done(let slug):               return ""\(slug)" is ready"
        case .failed(let msg):              return "Error: \(msg)"
        default:                            return ""
        }
    }

    private var subtitleText: String? {
        if case .generating(let ch, let p, let total) = service.state {
            return "Chapter \(ch + 1) · Paragraph \(p + 1) of \(total)"
        }
        return nil
    }
}
