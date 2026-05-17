import SwiftUI

struct TTSProgressBanner: View {
    let service: TTSGenerationService

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            if let progress = generationProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * progress)
                            .animation(.linear(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            } else {
                Spacer().frame(height: 14)
            }

            HStack(spacing: 12) {
                // Icon
                waveformIcon

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Controls
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
    }

    // MARK: - Waveform icon

    private var waveformIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 42, height: 42)

            switch service.state {
            case .generating:
                Image(systemName: "waveform")
                    .font(.body.bold())
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(.body.bold())
                    .foregroundStyle(Color.accentColor)
            case .finalizingAudio:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.bold())
                    .foregroundStyle(Color.accentColor)
            default:
                Image(systemName: "waveform")
                    .font(.body.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        Group {
            switch service.state {
            case .generating:
                Button {
                    service.pause()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            case .paused:
                Button {
                    service.resume()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Text

    private var titleText: String {
        switch service.state {
        case .preparingModel:   return "Preparing voice model…"
        case .generating:       return "Generating audiobook"
        case .paused:           return "Generation paused"
        case .finalizingAudio:  return "Finalizing audio…"
        case .done(let slug):   return "\"\(slug)\" is ready"
        case .failed(let msg):  return "Error: \(msg)"
        default:                return ""
        }
    }

    private var subtitleText: String {
        switch service.state {
        case .generating(let ch, let p, let total):
            let pct = total > 0 ? Int(Double(p) / Double(total) * 100) : 0
            return "Chapter \(ch + 1) · \(pct)% complete"
        case .paused:
            return "Tap play to continue"
        case .preparingModel:
            return "Loading on-device model…"
        case .finalizingAudio:
            return "Encoding to M4A…"
        default:
            return ""
        }
    }

    private var generationProgress: Double? {
        if case .generating(_, let p, let total) = service.state, total > 0 {
            return Double(p) / Double(total)
        }
        return nil
    }
}
