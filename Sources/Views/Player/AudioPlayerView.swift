import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette
    @ObservedObject var session: ReaderSession

    @State private var showSettings = false
    @State private var showChapters = false
    @State private var showMoreOptions = false
    @State private var showVoices = false
    @State private var isParagraphScrolledAway = false

    // Bookmark Toast notification states
    @State private var showToast = false
    @State private var toastMessage = ""

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
        palette.appBackground
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
                if appState.hideText {
                    listeningModeCanvas(geometry: geometry)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Spacer().frame(height: geometry.safeAreaInsets.top + (areControlsVisible ? 76 : 24))

                            let chapter = session.document.chapters[session.currentChapterIndex]
                            let firstIsTitle = !chapter.paragraphs.isEmpty &&
                                chapter.paragraphs[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
                                .caseInsensitiveCompare(chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                            
                            // Chapter Title Header
                            if firstIsTitle {
                                let isCurrent = session.currentParagraphIndex == 0
                                let attributedTitle = isCurrent ? makeAttributedParagraph(chapter.title) : AttributedString(chapter.title)
                                Text(attributedTitle)
                                    .font(.j7BookTitle(size: 26, family: appState.selectedFontFamily))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineSpacing(6)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 10)
                                    .padding(.bottom, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(isCurrent ? palette.activeParagraphBg : Color.clear)
                                    )
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(key: ActiveParagraphFramePreferenceKey.self, value: isCurrent ? geo.frame(in: .global) : .zero)
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    .gesture(
                                        TapGesture(count: 2)
                                            .onEnded {
                                                session.jumpToParagraph(0)
                                            }
                                            .exclusively(before: TapGesture(count: 1)
                                                .onEnded {
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                        areControlsVisible.toggle()
                                                    }
                                                    if areControlsVisible {
                                                        resetAutoHideTimer()
                                                    } else {
                                                        cancelAutoHideTimer()
                                                    }
                                                }
                                            )
                                    )
                                    .id(0)
                            } else {
                                Text(chapter.title)
                                    .font(.j7BookTitle(size: 26, family: appState.selectedFontFamily))
                                    .padding(.horizontal, 24)
                                    .padding(.top, 10)
                                    .padding(.bottom, 16)
                                    .foregroundStyle(palette.textPrimary)
                            }
                            
                            let startIndex = firstIsTitle ? 1 : 0
                            ForEach(startIndex..<chapter.paragraphs.count, id: \.self) { pIdx in
                                let para = chapter.paragraphs[pIdx]
                                let isCurrent = session.currentParagraphIndex == pIdx
                                
                                paragraphView(para: para, pIdx: pIdx, isCurrent: isCurrent)
                                    .id(pIdx)
                                    .accessibilityIdentifier("paragraph_row_\(pIdx)")
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

                // Premium floating bookmark toast notification
                if showToast {
                    HStack(spacing: 8) {
                        Image(systemName: toastMessage.contains("Added") ? "bookmark.fill" : "bookmark")
                            .font(.j7CaptionBold)
                            .foregroundStyle(.white)
                        Text(toastMessage)
                            .font(.j7CaptionBold)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, geometry.safeAreaInsets.top + 70) // perfect placement below header
                    .zIndex(100)
                }

                // Immersive floating "Sync Highlight" pill for one-tap snapping in full screen
                if !areControlsVisible && isParagraphScrolledAway {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
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
                            isParagraphScrolledAway = false
                            lastScrolledParagraphIndex = nil
                            lastScrolledSentenceRange = nil
                            lastScrollTime = Date.distantPast
                            
                            checkAndCenterHighlight(scrollProxy: scrollProxy, screenHeight: geometry.size.height)
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
                
                // If user manually scrolled away, do NOT snap back!
                guard !isParagraphScrolledAway else { return }
                
                lastScrolledParagraphIndex = newIdx
                lastScrolledSentenceRange = nil
                
                // Smooth initial scroll fallback towards the focus line (anchor: 0.15)
                // This starts the transition smoothly before geometry is measured
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                    scrollProxy.scrollTo(newIdx, anchor: UnitPoint(x: 0.5, y: 0.15))
                }
            }
            .onChange(of: session.currentChapterIndex) { _, newChIdx in
                isParagraphScrolledAway = false
                lastScrolledParagraphIndex = 0
                lastScrolledSentenceRange = nil
                lastScrolledProgress = 0.0
                lastScrollTime = Date()
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    scrollProxy.scrollTo(0, anchor: .top)
                }
            }
            .onChange(of: session.activeWordRange) { _, _ in
                checkAndCenterHighlight(scrollProxy: scrollProxy, screenHeight: geometry.size.height)
            }
            .onChange(of: session.state) { _, newState in
                if newState == .playing {
                    resetAutoHideTimer()
                    // Snapping back on play resume establishes perfect reader flow!
                    isParagraphScrolledAway = false
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(ActiveParagraphFramePreferenceKey.self) { rect in
                guard rect != .zero else { return }
                self.activeParagraphRect = rect
                
                // Align viewport focus precisely using the resolved paragraph geometry!
                if !isParagraphScrolledAway && session.state == .playing {
                    checkAndCenterHighlight(scrollProxy: scrollProxy, screenHeight: geometry.size.height)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(session: session)
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showChapters) {
                AudioChapterPickerView(session: session)
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showVoices) {
                VoicesView(isLocked: true)
                    .environment(appState)
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showMoreOptions) {
                MoreOptionsSheet(session: session)
                    .environment(appState)
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showRepairSheet, onDismiss: {
                session.playbackError = nil
            }) {
                ModelDownloadView(synthesizer: appState.supertonicSynthesizer) {
                    appState.selectedEngine = .supertonic
                    session.switchToScheduler(appState.synthScheduler, voices: TTSVoice.loadAll())
                }
                .preferredColorScheme(.light)
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
        let attributed = isCurrent ? makeAttributedParagraph(para.text) : AttributedString(para.text)
        Text(attributed)
            .font(.j7BookContent(size: appState.fontSize, family: appState.selectedFontFamily, weight: isCurrent ? .medium : .regular))
            .foregroundStyle(isCurrent ? palette.textPrimary : palette.textSecondary)
            .lineSpacing(6)
            .padding(.horizontal, 24)
            .padding(.vertical, isCurrent ? 14 : 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? palette.activeParagraphBg : Color.clear)
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ActiveParagraphFramePreferenceKey.self, value: isCurrent ? geo.frame(in: .global) : .zero)
                }
            )
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        session.jumpToParagraph(pIdx)
                    }
                    .exclusively(before: TapGesture(count: 1)
                        .onEnded {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                areControlsVisible.toggle()
                            }
                            if areControlsVisible {
                                resetAutoHideTimer()
                            } else {
                                cancelAutoHideTimer()
                            }
                        }
                    )
            )
            .opacity(isCurrent ? 1.0 : 0.35)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCurrent)
    }

    private func amplitude(for index: Int, at time: TimeInterval) -> CGFloat {
        let speeds = [4.5, 6.0, 3.5, 7.0, 5.0, 6.5, 4.0, 5.5, 4.8, 6.2, 3.8, 7.2, 5.2, 6.7, 4.2]
        let phase = Double(index) * 0.8
        let sine = sin(time * speeds[index % speeds.count] + phase)
        let normalized = (sine + 1.0) / 2.0 // 0 to 1
        return CGFloat(0.1 + normalized * 0.9) // 0.1 to 1.0
    }

    @ViewBuilder
    private func listeningModeCanvas(geometry: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Elegant Cover Placeholder or Image
            if let data = session.document.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 190, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 15, x: 0, y: 10)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                        )
                    
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                        
                        Text(session.document.title)
                            .font(.j7SubheadlineSerifBold)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .lineLimit(3)
                        
                        if let author = session.document.author {
                            Text(author)
                                .font(.j7Caption)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 190, height: 280)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            }
            
            // Metadata Section
            VStack(spacing: 8) {
                Text(session.document.title)
                    .font(.j7BookTitle(size: 24, family: appState.selectedFontFamily))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineLimit(2)
                
                if let author = session.document.author {
                    Text(author)
                        .font(.j7SubheadlineBold)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineLimit(1)
                }
                
                let chapter = session.document.chapters[session.currentChapterIndex]
                Text(chapter.title)
                    .font(.j7CaptionBold)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            
            // Beautiful Flowing Animated Waveform for premium feel!
            HStack(spacing: 4) {
                ForEach(0..<15, id: \.self) { idx in
                    if session.state == .playing {
                        TimelineView(.animation) { timeline in
                            let value = amplitude(for: idx, at: timeline.date.timeIntervalSince1970)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: 5, height: max(6, value * 44))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 5, height: 6)
                    }
                }
            }
            .frame(height: 50)
            .padding(.top, 16)
            
            Spacer()
        }
        .padding(.top, geometry.safeAreaInsets.top + (areControlsVisible ? 76 : 24))
        .padding(.bottom, 220)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
    }

    private func checkAndCenterHighlight(scrollProxy: ScrollViewProxy, screenHeight: CGFloat) {
        guard !isParagraphScrolledAway, session.state == .playing else { return }
        
        let now = Date()
        // Extremely short cooldown (e.g. 0.3s) just to prevent double triggers during initial layout passes
        guard now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
        
        let currentParaIdx = session.currentParagraphIndex
        let chapters = session.document.chapters
        guard session.currentChapterIndex < chapters.count else { return }
        let chapter = chapters[session.currentChapterIndex]
        guard currentParaIdx < chapter.paragraphs.count else { return }
        let para = chapter.paragraphs[currentParaIdx]
        let currentSentenceRange = activeSentenceRange(in: para.text, for: session.activeWordRange)
        
        // Scroll ONLY if the sentence range has actually changed, OR the paragraph has changed
        guard currentSentenceRange != lastScrolledSentenceRange || lastScrolledParagraphIndex != currentParaIdx else { return }
        
        guard screenHeight > 0, activeParagraphRect != .zero else { return }
        
        let paragraphHeight = activeParagraphRect.height
        let viewportHeight = screenHeight
        let targetViewportAnchor = 0.35 // Mathematically locks the focus line at 35% from the top of the viewport
        
        let progress: Double
        if let sentenceRange = currentSentenceRange, para.text.count > 0 {
            // Align the start of the sentence to the focal line
            progress = Double(sentenceRange.location) / Double(para.text.count)
        } else if let range = session.activeWordRange, para.text.count > 0 {
            progress = Double(range.location) / Double(para.text.count)
        } else {
            progress = 0.0
        }
        
        // Mathematical Scroll Anchor Equation:
        // A aligns the progress fraction of the paragraph with the targetViewportAnchor fraction of the viewport.
        let diff = paragraphHeight - viewportHeight
        let anchorY: Double
        if abs(diff) > 1.0 {
            let calculated = (progress * paragraphHeight - targetViewportAnchor * viewportHeight) / diff
            anchorY = max(0.0, min(1.0, calculated))
        } else {
            anchorY = progress
        }
        
        lastScrollTime = now
        lastScrolledParagraphIndex = currentParaIdx
        lastScrolledSentenceRange = currentSentenceRange
        lastScrolledProgress = progress
        
        withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
            scrollProxy.scrollTo(currentParaIdx, anchor: UnitPoint(x: 0.5, y: anchorY))
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
        
        // Default: soft contrast for all text in active paragraph to establish focus
        attributed.foregroundColor = palette.textPrimary.opacity(0.45)
        
        guard let nsRange = session.activeWordRange,
              nsRange.location != NSNotFound,
              nsRange.location + nsRange.length <= para.utf16.count else {
            // Fall back to full contrast when not actively playing a word
            attributed.foregroundColor = palette.textPrimary
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
        
        // 2. Style the active sentence with high-contrast foreground and soft theme-specific background tint
        if let sentenceNSRange = activeSentenceRange,
           let sentenceRange = Range(sentenceNSRange, in: para) {
            if let start = AttributedString.Index(sentenceRange.lowerBound, within: attributed),
               let end = AttributedString.Index(sentenceRange.upperBound, within: attributed) {
                attributed[start..<end].foregroundColor = palette.textPrimary
                attributed[start..<end].backgroundColor = palette.activeSentenceBg.opacity(0.35)
            }
        }
        
        // 3. Style the active word with a gorgeous matte focus block
        if let range = Range(nsRange, in: para) {
            if let start = AttributedString.Index(range.lowerBound, within: attributed),
               let end = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[start..<end].backgroundColor = palette.activeWordBg
                attributed[start..<end].foregroundColor = palette.activeWordFg
            }
        }
        
        return attributed
    }

    private func header(scrollProxy: ScrollViewProxy, safeAreaTop: CGFloat) -> some View {
        HStack(spacing: 12) {
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
                VStack(alignment: .center, spacing: 2) {
                    Text(session.document.title)
                        .font(.j7Title3Serif)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)

                    let chapter = session.document.chapters[session.currentChapterIndex]
                    let displayTitle: String = {
                        let trimmed = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            return "Chapter \(session.currentChapterIndex + 1)"
                        }
                        let lowercase = trimmed.lowercased()
                        if lowercase.hasPrefix("chapter") || lowercase.hasPrefix("ch.") || lowercase.hasPrefix("ch ") {
                            return trimmed
                        }
                        return "Chapter \(session.currentChapterIndex + 1): \(trimmed)"
                    }()
                    Text(displayTitle)
                        .font(.j7Subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player_header_title_button")
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.j7BodyBold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("player_more_options_button")
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
            
            // Row 1: Sleek Progress Bar and Timers (Clean & minimal)
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

                // 3 Clean Timing Indicators Directly Under Progress Bar
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
            
            // Row 2: Playback Controls Row (Bookmark, SkipBack, Play/Pause Circle, SkipForward, Speed Menu)
            HStack(spacing: 0) {
                // Bookmark Button (Far Left)
                let isBookmarked = session.bookmarkedParagraphs.contains("\(session.currentChapterIndex)-\(session.currentParagraphIndex)")
                Button {
                    session.toggleBookmarkForCurrentParagraph()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    triggerToast(isBookmarked ? "Bookmark Removed" : "Bookmark Added")
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.j7BodyBold)
                        .foregroundStyle(isBookmarked ? Color.accentColor : Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                
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
                .accessibilityIdentifier("player_play_pause_button")
                
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
                
                // Speed Selector Pill (Far Right)
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
            
            // Row 3: Bottom Row with Perfectly Centered Voice Pill and Right Chapter Button
            HStack(spacing: 0) {
                // Symmetrical invisible spacer on the left to perfectly center the Voice pill
                Color.clear
                    .frame(width: 44, height: 44)
                
                Spacer()
                
                // Voice selector pill (Perfectly Center)
                Button {
                    showVoices = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform")
                            .font(.j7Caption)
                            .foregroundStyle(Color.accentColor)
                        Text(session.voice.name)
                            .font(.j7SubheadlineSerifBold)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Chapter selector list icon (Far Right)
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
                .accessibilityIdentifier("player_chapters_button")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
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

    private var bookTimingStats: (elapsed: String, remaining: String, total: String, remainingHuman: String) {
        let chapters = session.document.chapters
        guard !chapters.isEmpty else { return ("0:00", "0:00", "0:00", "0m") }
        
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
            formatSeconds(totalSeconds),
            formatSecondsLong(remainingSeconds)
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
        let s = Int(seconds) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        if s > 0 { return "\(s)s" }
        return "0s"
    }

    private func triggerToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                if toastMessage == message {
                    showToast = false
                }
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: workItem)
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var showUpgrade = false

    private var supertonicReady: Bool {
        if case .ready = appState.supertonicSynthesizer.modelState { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Mode") {
                    Toggle(isOn: Binding(
                        get: { appState.hideText },
                        set: { appState.hideText = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Listening Mode (Hide Text)")
                                .font(.j7SubheadlineSerifBold)
                            Text("Replaces reading canvas with a beautiful minimal layout.")
                                .font(.j7Caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Reading Theme") {
                    Picker("Theme", selection: Bindable(appState).selectedReadingTheme) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Text(theme.displayTitle).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
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

                Section("Font Family") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BookFontFamily.allCases) { family in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    appState.selectedFontFamily = family
                                } label: {
                                    VStack(spacing: 4) {
                                        Text("Aa")
                                            .font(Font.custom(family.postScriptName() ?? (family == .systemSerif ? "Times New Roman" : "Helvetica"), size: 20))
                                            .fontWeight(.medium)
                                        Text(family.displayName)
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .frame(width: 72, height: 60)
                                    .foregroundStyle(appState.selectedFontFamily == family ? Color.accentColor : Color.primary)
                                    .background(
                                        appState.selectedFontFamily == family 
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.primary.opacity(0.04)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                appState.selectedFontFamily == family
                                                ? Color.accentColor.opacity(0.3)
                                                : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Font Size") {
                    HStack(spacing: 20) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if appState.fontSize > 12 {
                                appState.fontSize -= 2
                            }
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 44, height: 44)
                                .background(Color.primary.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.fontSize <= 12)
                        
                        Spacer()
                        
                        Text("\(Int(appState.fontSize)) pt")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.primary)
                        
                        Spacer()
                        
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if appState.fontSize < 36 {
                                appState.fontSize += 2
                            }
                        } label: {
                            Image(systemName: "textformat.size.larger")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 44, height: 44)
                                .background(Color.primary.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.fontSize >= 36)
                    }
                    .padding(.vertical, 4)
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
            .navigationTitle("Settings")
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
                .preferredColorScheme(.light)
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
                .accessibilityIdentifier("chapter_row_\(chapter.index)")
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
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(session: session)
                    .environment(appState)
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showSleepTimerPicker) {
                SleepTimerView(session: session)
                    .preferredColorScheme(.light)
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
