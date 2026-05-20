import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: ReaderSession

    @State private var showSettings = false
    @State private var showChapters = false
    @State private var isDeckExpanded = false
    @State private var dragOffset: CGFloat = 0

    // Inactivity Auto-Hide controls state
    @State private var areControlsVisible = true
    @State private var autoHideWorkItem: DispatchWorkItem? = nil

    private var themeBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(hex: "0C0C0E") // Obsidian dark theme
        } else {
            return Color(hex: "F7F5F0") // Warm editorial paper background
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .top) {
                // Background cover to color the status bar and catch empty space taps
                themeBackgroundColor
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            areControlsVisible.toggle()
                        }
                        if areControlsVisible {
                            resetAutoHideTimer()
                        } else {
                            cancelAutoHideTimer()
                        }
                    }

                // The Editorial Serif Reader Canvas (Full Screen)
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Spacer().frame(height: 12) // Perfect editorial micro cushion before title

                        let chapter = session.document.chapters[session.currentChapterIndex]
                        
                        // Chapter Title Header in Georgia Serif
                        Text(chapter.title)
                            .font(.system(size: 26, weight: .bold, design: .serif))
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                            .padding(.bottom, 16)
                            .foregroundStyle(Color.accentColor)
                        
                        ForEach(0..<chapter.paragraphs.count, id: \.self) { pIdx in
                            let para = chapter.paragraphs[pIdx]
                            let isCurrent = session.currentParagraphIndex == pIdx
                            
                            paragraphView(para: para, pIdx: pIdx, isCurrent: isCurrent)
                                .id(pIdx)
                        }
                    }
                    .padding(.bottom, 30) // Balanced editorial bottom paragraph cushion
                }
                .padding(.top, areControlsVisible ? geometry.safeAreaInsets.top + 70 : geometry.safeAreaInsets.top + 20)
                .padding(.bottom, areControlsVisible ? 0 : 20)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        areControlsVisible.toggle()
                    }
                    if areControlsVisible {
                        resetAutoHideTimer()
                    } else {
                        cancelAutoHideTimer()
                    }
                }
                .onAppear {
                    scrollProxy.scrollTo(session.currentParagraphIndex, anchor: .center)
                    if session.state == .playing {
                        resetAutoHideTimer()
                    }
                }
                .onDisappear {
                    cancelAutoHideTimer()
                }
                .onChange(of: session.currentParagraphIndex) { _, newIdx in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        scrollProxy.scrollTo(newIdx, anchor: .center)
                    }
                    if areControlsVisible {
                        resetAutoHideTimer()
                    }
                }
                .onChange(of: session.state) { _, newState in
                    if newState == .playing {
                        resetAutoHideTimer()
                    } else {
                        cancelAutoHideTimer()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            areControlsVisible = true
                        }
                    }
                }

                // Floating translucent frosted Header at the top
                header(scrollProxy: scrollProxy, safeAreaTop: geometry.safeAreaInsets.top)
                    .offset(y: areControlsVisible ? 0 : -150)
                    .opacity(areControlsVisible ? 1.0 : 0.0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if areControlsVisible {
                    slidingPlayerDeck
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(session: session)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showChapters) {
                AudioChapterPickerView(session: session)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .statusBarHidden(!areControlsVisible)
        }
    }
}

    @ViewBuilder
    private func paragraphView(para: String, pIdx: Int, isCurrent: Bool) -> some View {
        if isCurrent {
            let attributed = makeAttributedParagraph(para)
            Text(attributed)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundStyle(Color.primary)
                .lineSpacing(6)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(hex: "EFECE6"))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if areControlsVisible {
                        session.jumpToParagraph(pIdx)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            areControlsVisible = true
                        }
                        resetAutoHideTimer()
                    }
                }
        } else {
            Text(para)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineSpacing(6)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    if areControlsVisible {
                        session.jumpToParagraph(pIdx)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            areControlsVisible = true
                        }
                        resetAutoHideTimer()
                    }
                }
        }
    }

    private func makeAttributedParagraph(_ para: String) -> AttributedString {
        var attributed = AttributedString(para)
        
        guard let nsRange = session.activeWordRange,
              nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= para.utf16.count else {
            return attributed
        }
        
        // 1. Find the sentence containing the active word range
        var activeSentenceRange: NSRange? = nil
        para.enumerateSubstrings(in: para.startIndex..<para.endIndex, options: .bySentences) { _, sentenceRange, _, stop in
            let nsSentenceRange = NSRange(sentenceRange, in: para)
            if nsRange.location >= nsSentenceRange.location && nsRange.location < nsSentenceRange.location + nsSentenceRange.length {
                activeSentenceRange = nsSentenceRange
                stop = true
            }
        }
        
        // 2. Style the active sentence with a beautiful subtle glowing background color
        if let sentenceNSRange = activeSentenceRange,
           let sentenceRange = Range(sentenceNSRange, in: para) {
            if let start = AttributedString.Index(sentenceRange.lowerBound, within: attributed),
               let end = AttributedString.Index(sentenceRange.upperBound, within: attributed) {
                if colorScheme == .dark {
                    attributed[start..<end].backgroundColor = Color(hex: "FFCC00").opacity(0.15) // Soft dark amber highlight
                } else {
                    attributed[start..<end].backgroundColor = Color(hex: "FFCC00").opacity(0.20) // Soft light gold highlight
                }
            }
        }
        
        // 3. Style the active word with the sharp yellow focus box
        if let range = Range(nsRange, in: para) {
            if let start = AttributedString.Index(range.lowerBound, within: attributed),
               let end = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[start..<end].backgroundColor = Color(hex: "FFCC00") // Yellow word-level highlight box
                attributed[start..<end].foregroundColor = .black
            }
        }
        
        return attributed
    }

    private func header(scrollProxy: ScrollViewProxy, safeAreaTop: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    .clipShape(Circle())
            }

            Spacer()
            
            VStack(spacing: 2) {
                Text(session.document.title)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .lineLimit(1)
                Text(session.document.author ?? "Unknown Author")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 160)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), in: Capsule())

            Spacer()

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        scrollProxy.scrollTo(session.currentParagraphIndex, anchor: .center)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .clipShape(Circle())
                }
                
                Button {
                    showSettings = true
                } label: {
                    Text("Aa")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .clipShape(Circle())
                }

                Button {
                    showChapters = true
                } label: {
                    Image(systemName: "book.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaTop + 8) // Dynamic padding to perfectly clear notch on all devices!
        .padding(.bottom, 12)
        .background(
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
            }
        )
    }

    private var slidingPlayerDeck: some View {
        VStack(spacing: 0) {
            // Drag indicator / header bar
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if value.translation.height < -50 {
                                    isDeckExpanded = true
                                } else if value.translation.height > 50 {
                                    isDeckExpanded = false
                                }
                                dragOffset = 0
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isDeckExpanded.toggle()
                    }
                }

            if isDeckExpanded {
                expandedDeckContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedDeckContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5),
            alignment: .top
        )
        .clipShape(RoundedRectangle(cornerRadius: isDeckExpanded ? 24 : 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: -5)
        .padding(.horizontal, isDeckExpanded ? 0 : 12)
        .padding(.bottom, isDeckExpanded ? 0 : 10)
        .offset(y: dragOffset)
    }

    private var collapsedDeckContent: some View {
        HStack(spacing: 16) {
            CoverImageView(id: session.document.id)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                let chapter = session.document.chapters[session.currentChapterIndex]
                Text(chapter.title)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .lineLimit(1)
                
                Text("Paragraph \(session.currentParagraphIndex + 1) of \(chapter.paragraphs.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 14) {
                Button {
                    session.skip(seconds: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                
                Button {
                    session.togglePlay()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .opacity(session.isBuffering ? 0.3 : 1.0)
                        
                        if session.isBuffering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.9)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.05), in: Circle())
                }
                .foregroundStyle(Color.primary)

                Button {
                    session.skip(seconds: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    private var overallProgress: Double {
        guard !session.document.chapters.isEmpty else { return 0.0 }
        let totalChapters = Double(session.document.chapters.count)
        let currentChapter = Double(session.currentChapterIndex)
        let chapterWeight = 1.0 / totalChapters
        
        let currentChapterParagraphs = Double(session.document.chapters[session.currentChapterIndex].paragraphs.count)
        let currentParagraph = Double(session.currentParagraphIndex)
        let paragraphProgress = currentChapterParagraphs > 0 ? (currentParagraph / currentChapterParagraphs) : 0.0
        
        return (currentChapter / totalChapters) + (paragraphProgress * chapterWeight)
    }

    private var bookTimingStats: (elapsed: String, remaining: String, total: String) {
        let chapters = session.document.chapters
        guard !chapters.isEmpty else { return ("0:00", "0:00", "0:00") }
        
        let charsPerSecond = 15.0 // Average reading speed
        
        var totalChars = 0
        for ch in chapters {
            for para in ch.paragraphs {
                totalChars += para.count
            }
        }
        
        var elapsedChars = 0
        for chIdx in 0..<session.currentChapterIndex {
            for para in chapters[chIdx].paragraphs {
                elapsedChars += para.count
            }
        }
        let currentChapter = chapters[session.currentChapterIndex]
        for pIdx in 0..<session.currentParagraphIndex {
            elapsedChars += currentChapter.paragraphs[pIdx].count
        }
        
        let totalSeconds = Double(totalChars) / charsPerSecond / Double(session.playbackRate)
        let elapsedSeconds = Double(elapsedChars) / charsPerSecond / Double(session.playbackRate)
        let remainingSeconds = max(0, totalSeconds - elapsedSeconds)
        
        return (
            formatSeconds(elapsedSeconds),
            formatSecondsLong(remainingSeconds) + " left",
            formatSeconds(totalSeconds)
        )
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = Int(seconds) % 3600 / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatSecondsLong(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = Int(seconds) % 3600 / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var expandedDeckContent: some View {
        VStack(spacing: 20) {
            // Procedural Kinetic Waveform Visualizer
            KineticWaveformVisualizer(
                isPlaying: session.state == .playing,
                gender: session.voice.gender,
                rate: session.playbackRate
            )
            .frame(height: 50)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Dynamic Audio Progress Bar & Timing (Screen 1 style)
            let stats = bookTimingStats
            let progress = overallProgress
            
            VStack(spacing: 8) {
                // Slider timeline bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 24)
                
                // Timers Row: elapsed, remaining, total
                HStack {
                    Text(stats.elapsed)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(stats.remaining)
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Text(stats.total)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 8)

            // Chapter Info Pill
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
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08), in: Capsule())
            }

            // Central Transport controls row (Screen 1 style)
            HStack(spacing: 36) {
                let atFirst = session.currentChapterIndex == 0
                let atLast  = session.currentChapterIndex >= session.document.chapters.count - 1

                Button {
                    if !atFirst {
                        session.jumpToChapter(session.currentChapterIndex - 1)
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(atFirst ? Color.primary.opacity(0.2) : .primary)
                }

                Button {
                    session.skip(seconds: -30)
                } label: {
                    Image(systemName: "gobackward.30")
                        .font(.system(size: 24, weight: .semibold))
                }
                .foregroundStyle(Color.primary)

                Button {
                    session.togglePlay()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.primary.opacity(0.15), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .contentTransition(.symbolEffect(.replace))
                            .offset(x: session.state == .playing ? 0 : 2)
                            .opacity(session.isBuffering ? 0.2 : 1.0)
                        
                        if session.isBuffering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(colorScheme == .dark ? Color.black : Color.white)
                                .scaleEffect(1.4)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    session.skip(seconds: 30)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 24, weight: .semibold))
                }
                .foregroundStyle(Color.primary)

                Button {
                    if !atLast {
                        session.jumpToChapter(session.currentChapterIndex + 1)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(atLast ? Color.primary.opacity(0.2) : .primary)
                }
            }
            .foregroundStyle(Color.primary)
            
            // Bottom Options Row: Sleep, List, Speed Option
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 14))
                        Text("Sleep")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
                
                Spacer()
                
                Button {
                    showChapters = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                
                Spacer()
                
                Menu {
                    ForEach([0.8, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                        Button {
                            session.setRate(Float(rate))
                        } label: {
                            HStack {
                                Text(String(format: "%.2g× Speed", rate))
                                if abs(session.playbackRate - Float(rate)) < 0.05 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(format: "%.2g×", session.playbackRate))
                            .font(.system(size: 13, weight: .bold, design: .serif))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
            .padding(.horizontal, 16)
        }
    }

    private func resetAutoHideTimer() {
        autoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard session.state == .playing else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                areControlsVisible = false
            }
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: workItem)
    }

    private func cancelAutoHideTimer() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
    }
}

// Procedural 2026 Kinetic Audio Waveform Drawing View
struct KineticWaveformVisualizer: View {
    let isPlaying: Bool
    let gender: TTSVoice.Gender
    let rate: Float

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2

                // Setup parameters based on whether the voice is Male or Female, rate, and playback state
                let speedFactor = isPlaying ? CGFloat(rate) * 2.8 : 0.4
                let amplitudeFactor = isPlaying ? (gender == .male ? 20.0 : 14.0) : 3.0
                let frequencyFactor = gender == .male ? 0.015 : 0.028

                let t = timeline.date.timeIntervalSinceReferenceDate
                let currentPhase = t * speedFactor

                // Wave 1: Golden accent background wave
                var path1 = Path()
                path1.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, to: width, by: 2) {
                    let y = midY + sin(x * frequencyFactor + currentPhase) * amplitudeFactor
                    path1.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path1, with: .linearGradient(
                    Gradient(colors: [Color.accentColor.opacity(0.7), Color.orange.opacity(0.5)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: width, y: 0)
                ), lineWidth: 3.0)

                // Wave 2: Indigo accent main wave
                var path2 = Path()
                path2.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, to: width, by: 2) {
                    let y = midY + cos(x * (frequencyFactor * 0.85) - currentPhase * 1.3) * (amplitudeFactor * 0.75)
                    path2.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path2, with: .linearGradient(
                    Gradient(colors: [Color.accentColor, Color.purple.opacity(0.6)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: width, y: 0)
                ), lineWidth: 1.8)

                // Wave 3: White micro-highlight wave
                var path3 = Path()
                path3.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, to: width, by: 2) {
                    let y = midY + sin(x * (frequencyFactor * 1.45) + currentPhase * 0.85) * (amplitudeFactor * 0.35)
                    path3.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path3, with: .color(.primary.opacity(0.3)), lineWidth: 0.8)
            }
        }
    }
}

// Keep original SettingsSheet & AudioChapterPickerView structures but let's make sure SettingsSheet row is clean!
struct SettingsSheet: View {
    @ObservedObject var session: ReaderSession
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showUpgrade = false

    private var supertonicReady: Bool {
        if case .ready = appState.supertonicSynthesizer.modelState { return true }
        return false
    }
    private var appleVoices: [TTSVoice] { appState.appleVoiceScheduler.cachedVoices }

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    if supertonicReady {
                        ForEach(TTSVoice.loadAll()) { voice in voiceRow(voice) }
                    } else {
                        if appleVoices.isEmpty {
                            Text("No enhanced voices available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appleVoices) { voice in voiceRow(voice) }
                        }
                    }
                }

                if !supertonicReady {
                    Section {
                        Button {
                            showUpgrade = true
                        } label: {
                            Label("Download Supertonic for best quality", systemImage: "arrow.down.circle")
                        }
                    } footer: {
                        Text("Supertonic 3 is purpose-built for audiobooks (~400 MB, one-time download).")
                            .font(.caption)
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

                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { appState.selectedAppearance },
                        set: { appState.selectedAppearance = $0 }
                    )) {
                        ForEach(AppAppearance.allCases) { appAppearance in
                            Text(appAppearance.rawValue).tag(appAppearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if supertonicReady {
                    Section("Quality") {
                        Picker("Inference Steps", selection: $session.steps) {
                            Text("Fast").tag(2)
                            Text("Balanced").tag(4)
                            Text("High").tag(5)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("Aether Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showUpgrade) {
                ModelDownloadView(synthesizer: appState.supertonicSynthesizer) {
                    appState.selectedEngine = .supertonic
                    session.switchToScheduler(appState.synthScheduler, voices: TTSVoice.loadAll())
                }
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: TTSVoice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.system(.body, design: .serif).bold())
                Text(voice.language == "en" ? "English" : voice.language.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.voice.id == voice.id {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.setVoice(voice)
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
                            .font(.system(.body, design: .serif))
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
