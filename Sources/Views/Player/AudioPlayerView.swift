import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: ReaderSession

    @State private var showSettings = false
    @State private var showChapters = false
    @State private var showMoreOptions = false
    @State private var isDeckExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var isParagraphScrolledAway = false

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
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showSettings = true
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

                // Immersive floating "Sync Highlight" pill for one-tap snapping in full screen
                if !areControlsVisible && isParagraphScrolledAway {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Sync Highlight")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        .contentShape(Capsule())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                scrollProxy.scrollTo(session.currentParagraphIndex, anchor: .center)
                            }
                        }
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(ActiveParagraphFramePreferenceKey.self) { rect in
                guard rect != .zero else { return }
                let screenHeight = geometry.size.height
                let safeAreaTop = geometry.safeAreaInsets.top
                let safeAreaBottom = geometry.safeAreaInsets.bottom
                
                let isOffScreen = rect.maxY < (safeAreaTop + 60) || rect.minY > (screenHeight - safeAreaBottom - 60)
                
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.isParagraphScrolledAway = isOffScreen
                }
            }
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
            .sheet(isPresented: $showMoreOptions) {
                MoreOptionsSheet(session: session)
                    .environment(appState)
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ActiveParagraphFramePreferenceKey.self, value: geo.frame(in: .global))
                    }
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
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showSettings = true
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
                .onLongPressGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showSettings = true
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
        
        // 3. Style the active word with the soft amber focus box
        if let range = Range(nsRange, in: para) {
            if let start = AttributedString.Index(range.lowerBound, within: attributed),
               let end = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[start..<end].backgroundColor = Color(hex: "FFCC00").opacity(0.35) // Soft amber word-level highlight box
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
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scrollProxy.scrollTo(session.currentParagraphIndex, anchor: .center)
                }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.document.title)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    
                    let chapter = session.document.chapters[session.currentChapterIndex]
                    Text("Chapter \(session.currentChapterIndex + 1): \(chapter.title)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
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

    private var playerDeckBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(hex: "151517") // Deep obsidian/gray card background for premium contrast
        } else {
            return Color(hex: "FFFFFF") // Pure solid white card background to cover text completely
        }
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
                            if value.translation.height < -50 {
                                isDeckExpanded = true
                            } else if value.translation.height > 50 {
                                isDeckExpanded = false
                            }
                            dragOffset = 0
                        }
                )
                .onTapGesture {
                    isDeckExpanded.toggle()
                }

            if isDeckExpanded {
                expandedDeckContent
            } else {
                collapsedDeckContent
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(playerDeckBackgroundColor)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: -5)
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
            
            // Subtractive bottom controls row: Chapter Picker and ... More Options Button
            HStack(spacing: 12) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.08), in: Capsule())
                }
                
                Button {
                    showMoreOptions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
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

// Keep original SettingsSheet & AudioChapterPickerView structures but let's make sure SettingsSheet row is clean!
struct SettingsSheet: View {
    @ObservedObject var session: ReaderSession
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showUpgrade = false
    @State private var showVoices = false

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

                Section {
                    Button {
                        showVoices = true
                    } label: {
                        HStack {
                            Label("Manage Voices...", systemImage: "waveform.badge.mic")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showVoices) {
                VoicesView()
                    .environment(appState)
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

struct MoreOptionsSheet: View {
    @ObservedObject var session: ReaderSession
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showVoices = false
    @State private var showSettings = false
    @State private var showSleepTimerPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showVoices = true
                    } label: {
                        HStack(spacing: 12) {
                            FluidAvatarView(voice: session.voice)
                                .frame(width: 40, height: 40)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Narrator Voice")
                                    .font(.system(.body, design: .serif).bold())
                                Text(session.voice.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(Color.primary)
                } header: {
                    Text("Narrator")
                }
                
                Section {
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
                    .pickerStyle(.menu)
                    
                    Button {
                        showSleepTimerPicker = true
                    } label: {
                        HStack {
                            Text("Sleep Timer")
                                .font(.system(.body, design: .serif).bold())
                            Spacer()
                            
                            if session.sleepTimerOption != .off {
                                if let remaining = session.sleepTimerSecondsRemaining {
                                    Text(formatRemaining(remaining))
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Text(session.sleepTimerOption.rawValue)
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                            } else {
                                Text("Off")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(Color.primary)
                } header: {
                    Text("Controls")
                }
                
                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Visual Settings & Quality", systemImage: "slider.horizontal.3")
                            .font(.system(.body, design: .serif).bold())
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .navigationTitle("More Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showVoices) {
                VoicesView()
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(session: session)
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showSleepTimerPicker) {
                SleepTimerView(session: session)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
        }
    }
    
    private func formatRemaining(_ remaining: TimeInterval) -> String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct SleepTimerView: View {
    @ObservedObject var session: ReaderSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(SleepTimerOption.allCases) { option in
                    Button {
                        session.setSleepTimer(option)
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.rawValue)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(session.sleepTimerOption == option ? Color.accentColor : .primary)
                            
                            Spacer()
                            
                            if session.sleepTimerOption == option {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ActiveParagraphFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
