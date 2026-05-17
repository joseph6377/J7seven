import SwiftUI

struct PlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showReader = true
    @State private var showChapters = false
    @State private var showSpeedPicker = false
    @State private var showSleepPicker = false
    @State private var showTypography = false
    @State private var isDraggingScubber = false
    @State private var userScrolled = false
    @State private var scrubTime: Double = 0
    @State private var dragOffset: CGFloat = 0
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    private var player: PlayerService { appState.playerService }
    private var book: BookManifest { player.book! }
    private var chapter: Chapter { book.chapters[player.chapterIdx] }

    private var safeDuration: Double {
        player.duration.isFinite ? player.duration : 0
    }

    // All colors adapt to reader theme vs cover mode
    private var primaryColor: Color {
        showReader ? appState.readerTheme.textColor : .white
    }
    private var dimColor: Color {
        showReader ? appState.readerTheme.textColor.opacity(0.45) : .white.opacity(0.55)
    }
    private var panelBg: Color {
        showReader ? appState.readerTheme.background : Color(red: 0.08, green: 0.08, blue: 0.08)
    }
    private var navButtonBg: AnyShapeStyle {
        showReader
            ? AnyShapeStyle(appState.readerTheme.background.opacity(0.96))
            : AnyShapeStyle(Color.white.opacity(0.16))
    }

    /// Shadow that gives nav buttons visual depth on the reader page.
    /// No shadow in cover mode (dark background already provides contrast).
    private var navButtonShadow: Color {
        showReader ? .black.opacity(0.14) : .clear
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            if showReader {
                appState.readerTheme.background.ignoresSafeArea()
            } else {
                coverBackground
            }

            // Main content
            if showReader {
                readerLayer
            } else {
                coverLayer
            }

            // Soft gradient scrim behind the nav bar so scrolling text
            // doesn't bleed through the button circles.
            if showReader {
                LinearGradient(
                    colors: [
                        appState.readerTheme.background,
                        appState.readerTheme.background.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(controlsVisible ? 1 : 0)
            }

            // Floating nav bar — fades with controls
            navBar
                .padding(.top, 8)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)

            // Back to current highlight button
            if userScrolled {
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            userScrolled = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Back to current")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(primaryColor.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(primaryColor)
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    }
                    .padding(.bottom, controlsVisible ? 180 : 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Slide panel off the bottom when hidden so scroll area expands to full screen
            if controlsVisible {
                bottomPanel
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        .offset(y: max(0, dragOffset))
        .onAppear { scheduleHide() }
        .onChange(of: player.currentTime) { _, new in
            if !isDraggingScubber { scrubTime = new }
            appState.saveProgress()
        }
        .onChange(of: player.chapterIdx) { _, _ in
            appState.saveProgress()
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleHide()
            } else {
                hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
            }
        }
    }

    // MARK: - Auto-hide

    private func scheduleHide() {
        hideTask?.cancel()
        guard player.isPlaying else {
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, player.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    private func wake() {
        withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
        scheduleHide()
    }

    // MARK: - Cover background

    private var coverBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let cover = book.cover {
                    let url = BookPaths.localURL(slug: book.slug, filename: cover)
                    if let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 60)
                            .opacity(0.5)
                            .overlay(Color.black.opacity(0.5))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Floating nav bar

    private var navBar: some View {
        HStack(spacing: 0) {
            // Dismiss
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    .foregroundStyle(primaryColor)
                    .frame(width: 38, height: 38)
                    .background(navButtonBg, in: Circle())
                    .shadow(color: navButtonShadow, radius: 6, x: 0, y: 2)
            }

            // Centered drag-to-dismiss handle
            Capsule()
                .fill(primaryColor.opacity(0.35))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard value.translation.height > 0 else { return }
                            dragOffset = value.translation.height * 0.5
                        }
                        .onEnded { value in
                            if value.translation.height > 80 || value.velocity.height > 600 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )

            // Right: Aa + reader/cover toggle
            HStack(spacing: 8) {
                Button { showTypography = true } label: {
                    Text("Aa")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(primaryColor)
                        .frame(width: 38, height: 38)
                        .background(navButtonBg, in: Circle())
                        .shadow(color: navButtonShadow, radius: 6, x: 0, y: 2)
                }
                .sheet(isPresented: $showTypography) {
                    TypographySheetView().environment(appState)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showReader.toggle() }
                } label: {
                    Image(systemName: showReader ? "book.closed" : "text.alignleft")
                        .font(.body.bold())
                        .foregroundStyle(primaryColor)
                        .frame(width: 38, height: 38)
                        .background(navButtonBg, in: Circle())
                        .shadow(color: navButtonShadow, radius: 6, x: 0, y: 2)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Reader layer

    private var readerLayer: some View {
        ReaderView(
            slug: book.slug,
            chapter: chapter,
            fontSize: appState.readerFontSize,
            theme: appState.readerTheme,
            currentParagraphId: player.currentParagraphId,
            currentWordIdx: player.currentWordIdx,
            currentParagraphProgress: player.currentParagraphProgress,
            playbackRate: Double(player.playbackRate),
            controlsVisible: controlsVisible,
            isNarrating: player.isPlaying,
            userScrolled: $userScrolled,
            onReaderTapped: { wake() },
            onWordTapped: { paraId, wordIdx in seekToWord(paraId: paraId, wordIdx: wordIdx) }
        )
    }

    // MARK: - Cover layer

    private var coverLayer: some View {
        VStack(spacing: 0) {
            Spacer()

            if let cover = book.cover {
                let url = BookPaths.localURL(slug: book.slug, filename: cover)
                if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                }
            }

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                Text(chapter.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }

            Spacer()
        }
    }

    // MARK: - Bottom panel (always visible)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            scrubberBar
            VStack(spacing: 14) {
                timeRow
                transportRow
                secondaryRow
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .background(panelBg)
    }

    // Thin interactive progress bar spanning full width
    private var scrubberBar: some View {
        GeometryReader { geo in
            let pct = safeDuration > 0
                ? min(1, (isDraggingScubber ? scrubTime : player.currentTime) / safeDuration)
                : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(primaryColor.opacity(0.1))
                Rectangle()
                    .fill(primaryColor.opacity(0.72))
                    .frame(width: geo.size.width * pct)
            }
            .frame(height: 3)
            // Expand hit area vertically without changing visual height
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingScubber = true
                        scrubTime = min(1, max(0, value.location.x / geo.size.width)) * safeDuration
                    }
                    .onEnded { _ in
                        isDraggingScubber = false
                        player.seek(to: scrubTime)
                    }
            )
        }
        .frame(height: 23)
    }

    // Elapsed  ·  X left  ·  Total
    private var timeRow: some View {
        let elapsed = isDraggingScubber ? scrubTime : player.currentTime
        let remaining = max(0, safeDuration - elapsed)
        return HStack {
            Text(elapsed.formattedDuration)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(remaining.formattedDurationLong) left")
                .frame(maxWidth: .infinity, alignment: .center)
            Text(safeDuration.formattedDuration)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(dimColor)
    }

    // ⟲30   ▶/⏸   ⟳30  (flat, no circles)
    private var transportRow: some View {
        HStack {
            Spacer()
            Button {
                player.skip(seconds: -30)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "gobackward.30")
                    .font(.title)
                    .foregroundStyle(primaryColor)
            }
            Spacer()
            Button { togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(primaryColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button {
                player.skip(seconds: 30)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title)
                    .foregroundStyle(primaryColor)
            }
            Spacer()
        }
    }

    // Sleep · Chapters · Speed
    private var secondaryRow: some View {
        HStack {
            Button { showSleepPicker = true } label: {
                Label(sleepLabel, systemImage: "moon.fill")
                    .font(.caption.bold())
                    .foregroundStyle(dimColor)
            }
            .popover(isPresented: $showSleepPicker, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                SleepPopoverContent()
                    .environment(appState)
                    .presentationCompactAdaptation(.none)
            }

            Spacer()

            Button { showChapters = true } label: {
                Image(systemName: "list.bullet")
                    .font(.callout)
                    .foregroundStyle(dimColor)
            }
            .sheet(isPresented: $showChapters) {
                ChapterPickerView(book: book).environment(appState)
            }

            Spacer()

            Button { showSpeedPicker = true } label: {
                Text(speedLabel)
                    .font(.caption.bold())
                    .foregroundStyle(dimColor)
            }
            .popover(isPresented: $showSpeedPicker, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                SpeedPopoverContent()
                    .environment(appState)
                    .presentationCompactAdaptation(.none)
            }
        }
    }

    // MARK: - Helpers

    private func togglePlayback() {
        player.togglePlay()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        wake()
    }

    private func seekToWord(paraId: String, wordIdx: Int) {
        let paras = chapter.paragraphs
        guard let para = paras.first(where: { $0.id == paraId }) else { return }
        
        let relStart: Double
        if !para.wordEnds.isEmpty && wordIdx < para.wordEnds.count {
            relStart = wordIdx == 0 ? 0 : para.wordEnds[wordIdx - 1]
        } else {
            relStart = 0
        }
        
        player.seek(to: para.start + relStart)
        player.resume()
    }

    private var speedLabel: String {
        let r = player.playbackRate
        return r == Float(Int(r)) ? "\(Int(r))×" : String(format: "%.2g×", r)
    }

    private var sleepLabel: String {
        guard let end = player.sleepEndTime else { return "Sleep" }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 { return "Sleep" }
        let m = Int(remaining / 60)
        return m > 0 ? "\(m)m" : "<1m"
    }
}

// MARK: - Typography sheet

struct TypographySheetView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 28) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            VStack(spacing: 10) {
                Text("Text Size")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Button {
                        appState.setReaderFontSize(appState.readerFontSize - 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 14, design: .serif))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    Divider().frame(height: 40)
                    Text("\(Int(appState.readerFontSize))")
                        .font(.callout.monospacedDigit())
                        .frame(maxWidth: .infinity)
                    Divider().frame(height: 40)
                    Button {
                        appState.setReaderFontSize(appState.readerFontSize + 1)
                    } label: {
                        Text("A")
                            .font(.system(size: 22, design: .serif))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(Color(.secondarySystemBackground),
                             in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(spacing: 10) {
                Text("Theme")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        let isSelected = appState.readerTheme == theme
                        Button { appState.setReaderTheme(theme) } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(theme.background)
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Circle().stroke(
                                                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                                lineWidth: isSelected ? 2.5 : 1
                                            )
                                        )
                                    Text("Aa")
                                        .font(.system(size: 13, weight: .bold, design: .serif))
                                        .foregroundStyle(theme.textColor)
                                }
                                Text(theme.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Speed popover

struct SpeedPopoverContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Text("Playback Speed")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 6)

            HStack(spacing: 2) {
                ForEach(speeds, id: \.self) { s in
                    let isSelected = abs(appState.playerService.playbackRate - s) < 0.01
                    Button {
                        appState.playerService.setSpeed(s)
                        dismiss()
                    } label: {
                        Text(s == Float(Int(s)) ? "\(Int(s))×" : String(format: "%.2g×", s))
                            .font(.callout.bold())
                            .frame(width: 52, height: 40)
                            .background(isSelected ? Color.accentColor : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 336)
    }
}

// MARK: - Sleep popover

struct SleepPopoverContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    private let options: [(label: String, minutes: Double?)] = [
        ("Off", nil), ("5m", 5), ("15m", 15), ("30m", 30), ("1h", 60)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Sleep Timer")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 6)

            HStack(spacing: 2) {
                ForEach(options, id: \.label) { opt in
                    let isSelected = opt.minutes == nil && appState.playerService.sleepEndTime == nil
                    Button {
                        appState.playerService.setSleep(minutes: opt.minutes)
                        dismiss()
                    } label: {
                        Text(opt.label)
                            .font(.callout.bold())
                            .frame(width: 60, height: 40)
                            .background(isSelected ? Color.accentColor : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 336)
    }
}

// MARK: - Chapter picker

struct ChapterPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let book: BookManifest

    var body: some View {
        NavigationStack {
            List(Array(book.chapters.enumerated()), id: \.element.id) { idx, ch in
                Button {
                    appState.playerService.loadChapter(idx: idx, startTime: 0, shouldPlay: true)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: idx == appState.playerService.chapterIdx ? "play.fill" : "\(idx + 1).circle")
                            .foregroundStyle(idx == appState.playerService.chapterIdx ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading) {
                            Text(ch.title).foregroundStyle(.primary)
                            Text(ch.duration.formattedDurationLong).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
