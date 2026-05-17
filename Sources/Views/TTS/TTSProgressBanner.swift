import SwiftUI
import AVFoundation

struct TTSProgressBanner: View {
    @Environment(AppState.self) private var appState
    let service: TTSGenerationService
    @State private var showChapters = false
    @State private var showPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if let pct = generationProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemFill))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * pct)
                            .animation(.linear(duration: 0.4), value: pct)
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
                waveformIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Chapter selector — visible once at least 1 chapter is done
                if service.completedChapterCount > 0 {
                    Button {
                        showChapters = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Chapters")
                                .font(.caption.bold())
                            Image(systemName: "chevron.up")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        .sheet(isPresented: $showChapters) {
            LiveChapterPickerView(service: service, showPlayer: $showPlayer)
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView().environment(appState)
        }
    }

    // MARK: - Icon

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
                Button { service.pause() } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            case .paused:
                Button { service.resume() } label: {
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

    // MARK: - Computed text

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
            return "\(service.completedChapterCount) chapter\(service.completedChapterCount == 1 ? "" : "s") ready to play"
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

// MARK: - Live chapter picker

private struct LiveChapterPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let service: TTSGenerationService
    @Binding var showPlayer: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let info = service.liveBook, service.completedChapterCount > 0 {
                    chapterList(info: info)
                } else {
                    Text("No chapters ready yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Ready to Listen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func chapterList(info: LiveBookInfo) -> some View {
        List {
            Section {
                ForEach(0..<service.completedChapterCount, id: \.self) { idx in
                    Button {
                        playChapter(info: info, idx: idx)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(isCurrentChapter(info: info, idx: idx)
                                          ? Color.accentColor
                                          : Color(.secondarySystemBackground))
                                    .frame(width: 36, height: 36)

                                if isCurrentChapter(info: info, idx: idx) && appState.playerService.isPlaying {
                                    Image(systemName: "waveform")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .symbolEffect(.variableColor.iterative)
                                } else {
                                    Text("\(idx + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(isCurrentChapter(info: info, idx: idx) ? .white : .secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(idx < info.chapterTitles.count ? info.chapterTitles[idx] : "Chapter \(idx + 1)")
                                    .foregroundStyle(isCurrentChapter(info: info, idx: idx) ? Color.accentColor : .primary)
                                    .lineLimit(2)
                                Text(chapterDuration(info: info, idx: idx))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isCurrentChapter(info: info, idx: idx) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(service.completedChapterCount) of \(service.liveBook?.chapterTitles.count ?? 0) chapters ready")
                    .font(.caption)
            }

            if service.completedChapterCount < (service.liveBook?.chapterTitles.count ?? 0) {
                Section {
                    ForEach(service.completedChapterCount..<(service.liveBook?.chapterTitles.count ?? service.completedChapterCount), id: \.self) { idx in
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color(.systemFill))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text("\(idx + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.quaternary)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(idx < (service.liveBook?.chapterTitles.count ?? 0)
                                     ? service.liveBook!.chapterTitles[idx]
                                     : "Chapter \(idx + 1)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text("Generating…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Still generating")
                        .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func playChapter(info: LiveBookInfo, idx: Int) {
        let manifest = liveManifest(info: info)
        appState.playerService.play(book: manifest, chapterIdx: idx, time: 0)
        dismiss()
        showPlayer = true
    }

    private func isCurrentChapter(info: LiveBookInfo, idx: Int) -> Bool {
        appState.playerService.book?.slug == info.slug && appState.playerService.chapterIdx == idx
    }

    /// Build a BookManifest from the M4A files already on disk.
    private func liveManifest(info: LiveBookInfo) -> BookManifest {
        let chapters: [Chapter] = (0..<service.completedChapterCount).map { idx in
            let audio = "ch-\(idx).m4a"
            let url = BookPaths.localURL(slug: info.slug, filename: audio)
            let dur = m4aDuration(url: url)
            let title = idx < info.chapterTitles.count ? info.chapterTitles[idx] : "Chapter \(idx + 1)"
            return Chapter(title: title, slug: "ch-\(idx)", audio: audio,
                           html: "", duration: dur, paragraphs: [])
        }
        return BookManifest(
            id:       info.slug,
            slug:     info.slug,
            title:    info.title,
            author:   info.author,
            cover:    info.coverFilename,
            duration: chapters.reduce(0) { $0 + $1.duration },
            chapters: chapters
        )
    }

    private func chapterDuration(info: LiveBookInfo, idx: Int) -> String {
        let url = BookPaths.localURL(slug: info.slug, filename: "ch-\(idx).m4a")
        let dur = m4aDuration(url: url)
        return dur > 0 ? dur.formattedDurationLong : "—"
    }

    /// Synchronously reads frame count from an M4A/AAC file via AVAudioFile.
    private func m4aDuration(url: URL) -> Double {
        guard let f = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = f.processingFormat.sampleRate
        return rate > 0 ? Double(f.length) / rate : 0
    }
}
