import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: ReaderSession

    @State private var showSettings = false
    @State private var showChapters = false
    @State private var showMoreOptions = false
    @State private var showVoices = false
    @State private var isMuted = false
    @State private var isParagraphScrolledAway = false

    // Inactivity Auto-Hide controls state
    @State private var areControlsVisible = true
    @State private var autoHideWorkItem: DispatchWorkItem? = nil

    // Playback Error and Repair states
    @State private var showRepairSheet = false
    @State private var showErrorAlert = false
    @State private var activeError: (any Error)? = nil

    // Auto-scroll tracking state
    @State private var lastScrolledParagraphIndex: Int? = nil
    @State private var lastScrolledSentenceRange: NSRange? = nil
    @State private var lastScrolledProgress: Double = 0.0
    @State private var activeParagraphRect: CGRect = .zero
    @State private var lastScrollTime = Date.distantPast

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
                        Spacer().frame(height: geometry.safeAreaInsets.top + (areControlsVisible ? 76 : 24))

                        let chapter = session.document.chapters[session.currentChapterIndex]
                        
                        // Chapter Title Header in Georgia Serif
                        Text(chapter.title)
                            .font(.j7Title1Serif)
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
                    .padding(.bottom, 220) // Sizable cushion to easily scroll past the new floating player panel!
                }
                .ignoresSafeArea(edges: .all)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5).onChanged { _ in
                        if !isParagraphScrolledAway {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isParagraphScrolledAway = true
                            }
                        }
                    }
                )
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
                    let currentParaIdx = session.currentParagraphIndex
                    let chapters = session.document.chapters
                    let progress: Double
                    if session.currentChapterIndex < chapters.count {
                        let chapter = chapters[session.currentChapterIndex]
                        if currentParaIdx < chapter.paragraphs.count {
                            let para = chapter.paragraphs[currentParaIdx]
                            if let range = session.activeWordRange, para.text.count > 0 {
                                progress = Double(range.location) / Double(para.text.count)
                            } else {
                                progress = 0.0
                            }
                        } else {
                            progress = 0.0
                        }
                    } else {
                        progress = 0.0
                    }
                    
                    lastScrolledParagraphIndex = currentParaIdx
                    lastScrolledSentenceRange = nil
                    lastScrolledProgress = progress
                    lastScrollTime = Date()
                    
                    scrollProxy.scrollTo(currentParaIdx, anchor: UnitPoint(x: 0.5, y: progress))
                    
                    if session.state == .playing {
                        resetAutoHideTimer()
                    }
                }
                .onDisappear {
                    cancelAutoHideTimer()
                }
                .onChange(of: session.currentParagraphIndex) { _, newIdx in
                    if areControlsVisible {
                        resetAutoHideTimer()
                    }
                    
                    // As decided: if user manually scrolled away, do NOT snap back!
                    guard !isParagraphScrolledAway else { return }
                    
                    lastScrolledParagraphIndex = newIdx
                    lastScrolledSentenceRange = nil
                    lastScrolledProgress = 0.0
                    lastScrollTime = Date()
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        scrollProxy.scrollTo(newIdx, anchor: .center)
                    }
                }
                .onChange(of: session.activeWordRange) { _, _ in
                    checkAndCenterHighlight(scrollProxy: scrollProxy, screenHeight: geometry.size.height)
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
                .onChange(of: session.playbackError != nil) { _, hasError in
                    if hasError, let error = session.playbackError {
                        let desc = error.localizedDescription
                        if desc.contains("Model not loaded") || desc.contains("Model file missing") {
                            showRepairSheet = true
                        } else {
                            activeError = error
                            showErrorAlert = true
                        }
                    }
                }

                // Top status-bar gradient overlay to fade text under battery/time section
                LinearGradient(
                    colors: [themeBackgroundColor, themeBackgroundColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.safeAreaInsets.top + 24)
                .ignoresSafeArea(edges: .top)
                .opacity(areControlsVisible ? 0.0 : 1.0)
                .allowsHitTesting(false)

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
                                .font(.j7Caption2Bold)
                            Text("Sync Highlight")
                                .font(.j7CaptionBold)
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
                            let currentParaIdx = session.currentParagraphIndex
                            let chapters = session.document.chapters
                            let progress: Double
                            if session.currentChapterIndex < chapters.count {
                                let chapter = chapters[session.currentChapterIndex]
                                if currentParaIdx < chapter.paragraphs.count {
                                    let para = chapter.paragraphs[currentParaIdx]
                                    if let range = session.activeWordRange, para.text.count > 0 {
                                        progress = Double(range.location) / Double(para.text.count)
                                    } else {
                                        progress = 0.0
                                    }
                                } else {
                                    progress = 0.0
                                }
                            } else {
                                progress = 0.0
                            }
                            
                            isParagraphScrolledAway = false
                            lastScrolledParagraphIndex = currentParaIdx
                            lastScrolledSentenceRange = nil
                            lastScrolledProgress = progress
                            lastScrollTime = Date()
                            
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                scrollProxy.scrollTo(currentParaIdx, anchor: UnitPoint(x: 0.5, y: progress))
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

                if areControlsVisible {
                    VStack {
                        Spacer()
                        floatingPlayerPanel
                            .padding(.horizontal, 20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(ActiveParagraphFramePreferenceKey.self) { rect in
                guard rect != .zero else { return }
                self.activeParagraphRect = rect
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(session: session)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showChapters) {
                AudioChapterPickerView(session: session)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showVoices) {
                VoicesView(isLocked: true)
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showMoreOptions) {
                MoreOptionsSheet(session: session)
                    .environment(appState)
                    .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .sheet(isPresented: $showRepairSheet, onDismiss: {
                session.playbackError = nil
            }) {
                ModelDownloadView(synthesizer: appState.supertonicSynthesizer) {
                    appState.selectedEngine = .supertonic
                    session.switchToScheduler(appState.synthScheduler, voices: TTSVoice.loadAll())
                }
                .preferredColorScheme(appState.selectedAppearance.colorScheme)
            }
            .alert("Playback Error", isPresented: $showErrorAlert, presenting: activeError) { _ in
                Button("OK", role: .cancel) {
                    session.playbackError = nil
                }
            } message: { error in
                Text(error.localizedDescription)
            }
            .statusBarHidden(!areControlsVisible)
        }
    }
}

    @ViewBuilder
    private func paragraphView(para: Paragraph, pIdx: Int, isCurrent: Bool) -> some View {
        if isCurrent {
            let attributed = makeAttributedParagraph(para.text)
            Text(attributed)
                .font(.j7BookContent(size: appState.fontSize, weight: .medium))
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
            Text(para.text)
                .font(.j7BookContent(size: appState.fontSize))
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

    private func checkAndCenterHighlight(scrollProxy: ScrollViewProxy, screenHeight: CGFloat) {
        guard !isParagraphScrolledAway, session.state == .playing else { return }
        
        // Cooldown check to prevent animation feedback loop (e.g. 0.8 seconds between programmatic scrolls)
        let now = Date()
        guard now.timeIntervalSince(lastScrollTime) > 0.8 else { return }
        
        let currentParaIdx = session.currentParagraphIndex
        let chapters = session.document.chapters
        guard session.currentChapterIndex < chapters.count else { return }
        let chapter = chapters[session.currentChapterIndex]
        guard currentParaIdx < chapter.paragraphs.count else { return }
        let para = chapter.paragraphs[currentParaIdx]
        
        let progress: Double
        if let range = session.activeWordRange, para.text.count > 0 {
            progress = Double(range.location) / Double(para.text.count)
        } else {
            progress = 0.0
        }
        
        guard screenHeight > 0, activeParagraphRect != .zero else { return }
        
        let highlightY = activeParagraphRect.minY + (activeParagraphRect.height * progress)
        let relativeY = highlightY / screenHeight
        
        // Dynamic edge threshold: Scroll to center ONLY if the active highlighted word is about to move off-screen (outside [0.15, 0.85] band)
        if relativeY < 0.15 || relativeY > 0.85 {
            lastScrollTime = now
            lastScrolledParagraphIndex = currentParaIdx
            lastScrolledProgress = progress
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                scrollProxy.scrollTo(currentParaIdx, anchor: UnitPoint(x: 0.5, y: max(0.0, min(1.0, progress))))
            }
        }
    }

    private func activeSentenceRange(in para: String, for wordRange: NSRange?) -> NSRange? {
        guard let nsRange = wordRange,
              nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= para.utf16.count else {
            return nil
        }
        var activeSentenceRange: NSRange? = nil
        para.enumerateSubstrings(in: para.startIndex..<para.endIndex, options: .bySentences) { _, sentenceRange, _, stop in
            let nsSentenceRange = NSRange(sentenceRange, in: para)
            if nsRange.location >= nsSentenceRange.location && nsRange.location < nsSentenceRange.location + nsSentenceRange.length {
                activeSentenceRange = nsSentenceRange
                stop = true
            }
        }
        return activeSentenceRange
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
                    .font(.j7BodyBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    .clipShape(Circle())
            }

            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let currentParaIdx = session.currentParagraphIndex
                let chapters = session.document.chapters
                let progress: Double
                if session.currentChapterIndex < chapters.count {
                    let chapter = chapters[session.currentChapterIndex]
                    if currentParaIdx < chapter.paragraphs.count {
                        let para = chapter.paragraphs[currentParaIdx]
                        if let range = session.activeWordRange, para.text.count > 0 {
                            progress = Double(range.location) / Double(para.text.count)
                        } else {
                            progress = 0.0
                        }
                    } else {
                        progress = 0.0
                    }
                } else {
                    progress = 0.0
                }
                
                isParagraphScrolledAway = false
                lastScrolledParagraphIndex = currentParaIdx
                lastScrolledSentenceRange = nil
                lastScrolledProgress = progress
                lastScrollTime = Date()
                
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    scrollProxy.scrollTo(currentParaIdx, anchor: UnitPoint(x: 0.5, y: progress))
                }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.document.title)
                        .font(.j7SubheadlineSerifBold)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    
                    let chapter = session.document.chapters[session.currentChapterIndex]
                    Text("Chapter \(session.currentChapterIndex + 1): \(chapter.title)")
                        .font(.j7Caption2Bold)
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

    private var floatingPlayerPanel: some View {
        VStack(spacing: 16) {
            let stats = bookTimingStats
            let progress = overallProgress
            
            // Row 1: Sleek Progress Bar and Timers
            VStack(spacing: 8) {
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
                .padding(.horizontal, 20)
                
                HStack {
                    Text(stats.elapsed)
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(stats.remaining)
                        .font(.j7CaptionSerifBold)
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Text(stats.total)
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 16)
            
            // Row 2: Playback Controls Row (Mute, SkipBack, Play/Pause Circle, SkipForward, Speed Menu)
            HStack(spacing: 0) {
                // Mute Button
                Button {
                    isMuted.toggle()
                    if isMuted {
                        session.player.pause()
                    } else {
                        session.player.play()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.j7BodyBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                
                Spacer()
                
                // Skip backward (15s)
                Button {
                    session.skip(seconds: -15)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.j7Title3)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                // Center Play/Pause button
                Button {
                    session.togglePlay()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 58, height: 58)
                            .shadow(color: Color.primary.opacity(0.12), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                            .font(.j7Title1)
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .contentTransition(.symbolEffect(.replace))
                            .offset(x: (session.state == .playing || session.isBuffering) ? 0 : 2)
                            .opacity(session.isBuffering ? 0.2 : 1.0)
                        
                        if session.isBuffering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(colorScheme == .dark ? Color.black : Color.white)
                                .scaleEffect(1.1)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Skip forward (30s)
                Button {
                    session.skip(seconds: 30)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.j7Title3)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                // Speed Selector Pill (Right)
                Menu {
                    ForEach([Float(0.8), Float(1.0), Float(1.25), Float(1.5), Float(1.75), Float(2.0)], id: \.self) { rate in
                        Button {
                            session.setRate(rate)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Text(String(format: "%.2f×", rate))
                                if session.playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.1f×", session.playbackRate))
                        .font(.j7SubheadlineBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            
            // Row 3: Direct Utility Actions (Symmetrical balance spacer, Voice selector pill, Chapter button)
            HStack(spacing: 0) {
                // Font size picker (Left)
                Menu {
                    ForEach([14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0], id: \.self) { size in
                        Button {
                            appState.fontSize = size
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Text("\(Int(size)) pt" + (size == 18.0 ? " (Default)" : ""))
                                if appState.fontSize == size {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.j7BodyBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                
                Spacer()
                
                // Voice selector pill (Center)
                Button {
                    showVoices = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text(session.voice.name)
                        .font(.j7SubheadlineSerifBold)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Chapter selector list icon (Right)
                Button {
                    showChapters = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.j7BodyBold)
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 15, x: 0, y: 10)
    }

    private var overallProgress: Double {
        let chapters = session.document.chapters
        guard !chapters.isEmpty else { return 0.0 }
        
        var totalChars = 0
        for ch in chapters {
            for para in ch.paragraphs {
                totalChars += para.text.count
            }
        }
        guard totalChars > 0 else { return 0.0 }
        
        var elapsedChars = 0
        for chIdx in 0..<session.currentChapterIndex {
            for para in chapters[chIdx].paragraphs {
                elapsedChars += para.text.count
            }
        }
        let currentChapter = chapters[session.currentChapterIndex]
        for pIdx in 0..<session.currentParagraphIndex {
            elapsedChars += currentChapter.paragraphs[pIdx].text.count
        }
        if let range = session.activeWordRange, range.location != NSNotFound {
            elapsedChars += range.location
        }
        
        return Double(elapsedChars) / Double(totalChars)
    }

    private var bookTimingStats: (elapsed: String, remaining: String, total: String) {
        let chapters = session.document.chapters
        guard !chapters.isEmpty else { return ("0:00", "0:00", "0:00") }
        
        let charsPerSecond = 15.0 // Average reading speed
        
        var totalChars = 0
        for ch in chapters {
            for para in ch.paragraphs {
                totalChars += para.text.count
            }
        }
        
        var elapsedChars = 0
        for chIdx in 0..<session.currentChapterIndex {
            for para in chapters[chIdx].paragraphs {
                elapsedChars += para.text.count
            }
        }
        let currentChapter = chapters[session.currentChapterIndex]
        for pIdx in 0..<session.currentParagraphIndex {
            elapsedChars += currentChapter.paragraphs[pIdx].text.count
        }
        if let range = session.activeWordRange, range.location != NSNotFound {
            elapsedChars += range.location
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
                                .font(.j7Caption)
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
                                .font(.j7Caption2Bold)
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
                            .font(.j7Caption)
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
                            Text("Balanced").tag(5)
                            Text("High").tag(8)
                            Text("Ultra").tag(12)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: session.steps) { _, newValue in
                            session.setSteps(newValue)
                        }
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
                VoicesView(isLocked: true)
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
                    .font(.j7SubheadlineSerifBold)
                Text(voice.language == "en" ? "English" : voice.language.uppercased())
                    .font(.j7Caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.voice.id == voice.id {
                Image(systemName: "checkmark")
                    .font(.j7SubheadlineBold)
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
                            .font(.j7Caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(chapter.title)
                            .font(.j7BodySerif)
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Narrator Voice")
                                    .font(.j7SubheadlineSerifBold)
                                Text(session.voice.name)
                                    .font(.j7Caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.j7CaptionBold)
                                .foregroundStyle(.secondary.opacity(0.5))
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
                                .font(.j7SubheadlineSerifBold)
                            Spacer()
                            
                            if session.sleepTimerOption != .off {
                                if let remaining = session.sleepTimerSecondsRemaining {
                                    Text(formatRemaining(remaining))
                                        .font(.j7CaptionBold)
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Text(session.sleepTimerOption.rawValue)
                                        .font(.j7CaptionBold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            } else {
                                Text("Off")
                                    .font(.j7Caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.j7CaptionBold)
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
                            .font(.j7SubheadlineSerifBold)
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
                VoicesView(isLocked: true)
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
                                .font(.j7BodySerif)
                                .foregroundStyle(session.sleepTimerOption == option ? Color.accentColor : .primary)
                            
                            Spacer()
                            
                            if session.sleepTimerOption == option {
                                Image(systemName: "checkmark")
                                    .font(.j7SubheadlineBold)
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
