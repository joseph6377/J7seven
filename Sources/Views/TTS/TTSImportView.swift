import SwiftUI

struct TTSImportView: View {
    @Environment(\.dismiss) private var dismiss

    let epubURL: URL
    let generationService: TTSGenerationService
    let supertonicService: SupertonicService

    @State private var parsedBook: EpubTextParser.ParsedBook?
    @State private var parseError: String?
    @State private var selectedVoice: TTSVoice = .default
    @State private var selectedIndices: Set<Int> = []
    @State private var showModelDownload = false

    private let voices = TTSVoice.loadAll()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("New Audiobook")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await parseEPUB() }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView(service: supertonicService) {
                dismiss()
                generationService.generate(epubURL: epubURL, voice: selectedVoice,
                                           selectedIndices: selectedIndices)
            }
        }
    }

    // MARK: - Content switcher

    @ViewBuilder
    private var content: some View {
        if let error = parseError {
            errorView(error)
        } else if let book = parsedBook {
            importForm(book)
        } else {
            VStack(spacing: 16) {
                ProgressView()
                Text("Reading EPUB…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Main form

    private func importForm(_ book: EpubTextParser.ParsedBook) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header — cover + metadata
                    bookHeader(book)
                        .padding(.bottom, 24)

                    Divider()

                    // Chapter selection
                    chapterSection(book)

                    Divider()

                    // Voice selection
                    voiceSection
                        .padding(.bottom, 24)
                }
            }

            // Generate button
            generateButton
        }
    }

    // MARK: - Book header

    private func bookHeader(_ book: EpubTextParser.ParsedBook) -> some View {
        VStack(spacing: 12) {
            Group {
                if let data = book.coverData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [.purple, .indigo],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 100, height: 150)
                        .overlay(Image(systemName: "headphones")
                            .font(.system(size: 36, weight: .light)).foregroundStyle(.white.opacity(0.6)))
                }
            }
            .padding(.top, 24)

            VStack(spacing: 3) {
                Text(book.title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(book.author).foregroundStyle(.secondary).font(.subheadline)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Chapter selection

    private func chapterSection(_ book: EpubTextParser.ParsedBook) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chapters")
                        .font(.headline)
                    Text("\(selectedIndices.count) of \(book.chapters.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(selectedIndices.count == book.chapters.count ? "Deselect All" : "Select All") {
                    if selectedIndices.count == book.chapters.count {
                        selectedIndices = []
                    } else {
                        selectedIndices = Set(0..<book.chapters.count)
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            ForEach(Array(book.chapters.enumerated()), id: \.offset) { idx, ch in
                ChapterToggleRow(
                    index: idx,
                    chapter: ch,
                    isSelected: selectedIndices.contains(idx)
                ) {
                    if selectedIndices.contains(idx) {
                        selectedIndices.remove(idx)
                    } else {
                        selectedIndices.insert(idx)
                    }
                }
                if idx < book.chapters.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Voice section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(voices) { voice in
                    VoiceCard(voice: voice, isSelected: selectedVoice == voice)
                        .onTapGesture { selectedVoice = voice }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Generate button

    private var generateButton: some View {
        Button(action: startGeneration) {
            let count = selectedIndices.count
            Label(count == 0 ? "Select chapters above" : "Generate \(count) Chapter\(count == 1 ? "" : "s")",
                  systemImage: "waveform")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedIndices.isEmpty)
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Couldn't Read EPUB").font(.headline)
            Text(msg).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func parseEPUB() async {
        do {
            let book = try EpubTextParser.parse(epubURL: epubURL)
            parsedBook = book
            // Auto-select content chapters; deselect common front-matter by default
            selectedIndices = Set(book.chapters.indices.filter { !isFrontMatter(book.chapters[$0].title) })
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func isFrontMatter(_ title: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let frontMatterKeywords = [
            "cover", "title page", "also by", "copyright", "dedication",
            "epigraph", "table of contents", "contents", "half title",
            "about the author", "acknowledgment", "bibliography", "index",
            "notes", "permissions", "colophon", "frontispiece"
        ]
        return frontMatterKeywords.contains(where: { t == $0 || t.hasPrefix($0) })
    }

    private func startGeneration() {
        guard !selectedIndices.isEmpty else { return }
        switch supertonicService.modelState {
        case .notDownloaded, .error, .loading, .downloading:
            showModelDownload = true
        case .ready:
            dismiss()
            generationService.generate(epubURL: epubURL, voice: selectedVoice,
                                       selectedIndices: selectedIndices)
        }
    }
}

// MARK: - Chapter toggle row

private struct ChapterToggleRow: View {
    let index: Int
    let chapter: EpubChapter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(2)
                    Text("\(chapter.paragraphs.count) paragraph\(chapter.paragraphs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Voice card

private struct VoiceCard: View {
    let voice: TTSVoice
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: voice.gender == .male ? "person" : "person.fill")
                .font(.title)
            Text(voice.name).font(.subheadline.bold())
            Text(voice.language.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
