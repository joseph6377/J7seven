import SwiftUI

struct ReaderView: View {
    let slug: String
    let chapter: Chapter
    var fontSize: CGFloat
    var theme: ReaderTheme
    var currentParagraphId: String?
    var currentWordIdx: Int?
    var currentParagraphProgress: Double
    var playbackRate: Double
    var controlsVisible: Bool
    var isNarrating: Bool
    @Binding var userScrolled: Bool
    var onReaderTapped: (() -> Void)?
    var onWordTapped: ((String, Int) -> Void)?

    @State private var parsed: ParsedChapter = .empty
    @State private var isAutoScrolling = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let title = parsed.title {
                        Text(title)
                            .font(.serif(size: fontSize * 1.5))
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                            .padding(.top, 40)
                            .padding(.bottom, 20)
                    }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(parsed.paragraphs) { para in
                            paragraphView(para)
                        }
                    }
                    
                    // Bottom padding for player UI
                    Color.clear.frame(height: 150)
                }
                .contentShape(Rectangle())
            }
            .background(theme.background)
            .modifier(ScrollPhaseUserDetector(userScrolled: $userScrolled))
            .onChange(of: currentParagraphId) { _, newId in
                if let id = newId, !userScrolled {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isAutoScrolling = true
                        proxy.scrollTo(id, anchor: .center)
                    }
                    // Reset auto-scrolling flag after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isAutoScrolling = false
                    }
                }
            }
            // Also watch for userScrolled being reset externally (Back to sync)
            .onChange(of: userScrolled) { _, scrolled in
                if !scrolled, let id = currentParagraphId {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .task(id: chapter.id) {
            let loaded = await Self.load(slug: slug, htmlFile: chapter.html)
            parsed = loaded
            userScrolled = false
        }
    }

    @ViewBuilder
    private func paragraphView(_ para: ParsedParagraph) -> some View {
        let isActive = para.id == currentParagraphId
        let activeWordIdx: Int? = effectiveWordIdx(isActive: isActive, wordCount: para.words.count)

        VStack(alignment: .leading, spacing: 0) {
            WordWrapLayout(horizontalSpacing: 5, verticalSpacing: 12) {
                ForEach(Array(para.words.enumerated()), id: \.offset) { idx, word in
                    Button {
                        onWordTapped?(para.id, idx)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            userScrolled = false
                        }
                        onReaderTapped?()
                    } label: {
                        wordLabel(word, isCurrent: idx == activeWordIdx)
                    }
                    .buttonStyle(.plain)
                    .id("\(para.id)-word-\(idx)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(isActive ? theme.paraHighlight : Color.primary.opacity(0.001))
            .contentShape(Rectangle())
            .onTapGesture {
                onWordTapped?(para.id, 0)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    userScrolled = false
                }
                onReaderTapped?()
            }
        }
        .id(para.id)
    }

    @ViewBuilder
    private func wordLabel(_ word: String, isCurrent: Bool) -> some View {
        let fg: Color = isCurrent ? theme.highlightedWordTextColor : theme.textColor
        let bg: Color = isCurrent ? theme.wordHighlight : .clear
        Text(word)
            .font(.serif(size: fontSize))
            .foregroundStyle(fg)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg))
            .animation(.easeInOut(duration: 0.18), value: isCurrent)
            .contentShape(Rectangle())
    }

    /// Returns the word index to highlight inside a paragraph. Prefers `currentWordIdx`
    /// when the manifest provides word-level timing; otherwise interpolates evenly from
    /// `currentParagraphProgress`.
    private func effectiveWordIdx(isActive: Bool, wordCount: Int) -> Int? {
        guard isActive, wordCount > 0 else { return nil }
        if let idx = currentWordIdx { return min(idx, wordCount - 1) }
        let raw = Int(currentParagraphProgress * Double(wordCount))
        return min(max(raw, 0), wordCount - 1)
    }

    // MARK: - HTML parsing

    private static func load(slug: String, htmlFile: String) async -> ParsedChapter {
        let url = BookPaths.localURL(slug: slug, filename: htmlFile)
        guard let html = try? String(contentsOf: url, encoding: .utf8) else { return .empty }
        return await MainActor.run { parse(html) }
    }

    private static func parse(_ html: String) -> ParsedChapter {
        var title: String? = nil
        var paragraphs: [ParsedParagraph] = []

        if let h1 = match(html, pattern: #"<h1[^>]*>([\s\S]*?)</h1>"#).first?.last {
            title = decode(stripTags(h1))
        } else if let titleTag = match(html, pattern: #"<title[^>]*>([\s\S]*?)</title>"#).first?.last {
            title = decode(stripTags(titleTag))
        }

        // EPUB synchronized content often uses <span> tags for lines or sentences.
        // We look for any tag with an id="..."
        // Group 1: tag name, Group 2: ID, Group 3: inner content
        let pattern = #"<([a-zA-Z0-9]+)\s+[^>]*?id\s*=\s*"([^"]+)"[^>]*?>([\s\S]*?)</\1>"#
        let matches = match(html, pattern: pattern)
        
        let textTags = ["p", "div", "li", "span", "h1", "h2", "h3", "h4", "h5", "h6"]
        let skipTags = ["html", "head", "body", "link", "script", "style", "meta"]
        
        for m in matches {
            // Note: match() returns ONLY capture groups. 3 groups = count of 3.
            guard m.count >= 3 else { continue }
            let tag = m[0].lowercased()
            let id = m[1]
            let inner = m[2]
            
            if skipTags.contains(tag) { continue }
            
            // Try to find nested word spans if they exist (class="w")
            let wordMatches = match(inner, pattern: #"<span\s+[^>]*?class\s*=\s*"w"[^>]*?>([\s\S]*?)</span>"#)
            var words: [String] = []
            
            for wm in wordMatches {
                if let wText = wm.last {
                    words.append(decode(stripTags(wText)))
                }
            }
            
            if words.isEmpty && textTags.contains(tag) {
                // Split the tag content into words so the WordWrapLayout can wrap it correctly.
                let plainText = decode(stripTags(inner))
                if !plainText.isEmpty {
                    words = plainText.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                }
            }
            
            if !words.isEmpty {
                paragraphs.append(ParsedParagraph(id: id, words: words))
            }
        }

        return ParsedChapter(title: title, paragraphs: paragraphs)
    }

    private static func match(_ source: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            (1..<m.numberOfRanges).compactMap { i -> String? in
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
        }
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func decode(_ s: String) -> String {
        var r = s
        let map: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&hellip;", "…"), ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
            ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}")
        ]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Legacy-compatible scroll phase detector

private struct ScrollPhaseUserDetector: ViewModifier {
    @Binding var userScrolled: Bool

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        if !userScrolled { userScrolled = true }
                    }
            )
    }
}

// MARK: - Models

private struct ParsedChapter {
    let title: String?
    let paragraphs: [ParsedParagraph]
    static let empty = ParsedChapter(title: nil, paragraphs: [])
}

private struct ParsedParagraph: Identifiable {
    let id: String
    let words: [String]
}

// MARK: - Font Extension

private extension Font {
    static func serif(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

// MARK: - WordWrapLayout

private struct WordWrapLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(in: subviews, maxWidth: maxWidth)
        let width = rows.reduce(CGFloat.zero) { max($0, $1.width) }
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(in subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        let availableWidth = maxWidth.isFinite ? maxWidth : CGFloat.greatestFiniteMagnitude

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width

            if proposedWidth > availableWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }

            current.items.append(RowItem(subview: subview, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }
}
