import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: ReaderSession

    @State private var showSettings = false
    @State private var showChapters = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 16)

            coverArtSection

            Spacer(minLength: 16)

            metadataSection

            Spacer(minLength: 16)

            transportControls
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.black.ignoresSafeArea()
                .overlay { backgroundLayer }
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .sheet(isPresented: $showSettings) {
            SettingsSheet(session: session)
        }
        .sheet(isPresented: $showChapters) {
            AudioChapterPickerView(session: session)
        }
    }

    private var backgroundLayer: some View {
        CoverImageView(id: session.document.id)
            .ignoresSafeArea()
            .blur(radius: 60)
            .opacity(0.4)
            .overlay(Color.black.opacity(0.3))
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2), in: Circle())
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var coverArtSection: some View {
        CoverImageView(id: session.document.id)
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
    }

    private var metadataSection: some View {
        VStack(spacing: 8) {
            Text(session.document.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if let author = session.document.author {
                Text(author)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            let chapter = session.document.chapters[session.currentChapterIndex]
            Text(chapter.title)
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
        }
        .padding(.horizontal, 30)
    }

    private var transportControls: some View {
        VStack(spacing: 30) {
            // Speed indicator
            HStack {
                Spacer()
                Text(String(format: "%.2g×", session.playbackRate))
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }

            // Main buttons
            HStack(spacing: 28) {
                let atFirst = session.currentChapterIndex == 0
                let atLast  = session.currentChapterIndex >= session.document.chapters.count - 1

                Button {
                    if !atFirst { session.jumpToChapter(session.currentChapterIndex - 1) }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(atFirst ? Color.white.opacity(0.3) : .white)
                }

                Button {
                    session.skipPrevParagraph()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 28))
                }

                Button {
                    session.togglePlay()
                } label: {
                    Image(systemName: session.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 80))
                }

                Button {
                    session.skipNextParagraph()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 28))
                }

                Button {
                    if !atLast { session.jumpToChapter(session.currentChapterIndex + 1) }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(atLast ? Color.white.opacity(0.3) : .white)
                }
            }
            .foregroundStyle(.white)
            
            // Chapter picker button
            Button {
                showChapters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.caption.bold())
                    Text("Chapter \(session.currentChapterIndex + 1) of \(session.document.chapters.count)")
                        .font(.caption.bold())
                    Image(systemName: "chevron.up")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var session: ReaderSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    ForEach(TTSVoice.loadAll()) { voice in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                Text(voice.language).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.voice.id == voice.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            session.setVoice(voice)
                        }
                    }
                }

                Section("Speed") {
                    Picker("Playback Speed", selection: Binding(
                        get: { session.playbackRate },
                        set: { session.setRate($0) }
                    )) {
                        Text("0.8×").tag(Float(0.8))
                        Text("1.0×").tag(Float(1.0))
                        Text("1.25×").tag(Float(1.25))
                        Text("1.5×").tag(Float(1.5))
                        Text("1.75×").tag(Float(1.75))
                        Text("2.0×").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Quality") {
                    Picker("Inference Steps", selection: $session.steps) {
                        Text("Fast").tag(2)
                        Text("Balanced").tag(4)
                        Text("High").tag(5)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AudioChapterPickerView: View {
    @ObservedObject var session: ReaderSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(session.document.chapters) { chapter in
                Button {
                    session.jumpToChapter(chapter.index)
                    dismiss()
                } label: {
                    HStack {
                        Text("\(chapter.index + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(chapter.title)
                            .foregroundStyle(session.currentChapterIndex == chapter.index ? Color.accentColor : .primary)
                        Spacer()
                        if session.currentChapterIndex == chapter.index {
                            Image(systemName: "waveform")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
