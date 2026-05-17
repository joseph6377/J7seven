import SwiftUI

/// Sheet shown after the user picks a text-only EPUB.
/// Previews book metadata, lets the user choose a voice, then kicks off generation.
struct TTSImportView: View {
    @Environment(\.dismiss) private var dismiss

    let epubURL: URL
    let generationService: TTSGenerationService
    let supertonicService: SupertonicService

    @State private var parsedBook: EpubTextParser.ParsedBook? = nil
    @State private var parseError: String? = nil
    @State private var selectedVoice: TTSVoice = .default
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
                // Model is ready — auto-start generation
                dismiss()
                generationService.generate(epubURL: epubURL, voice: selectedVoice)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = parseError {
            errorView(error)
        } else if let book = parsedBook {
            bookPreview(book)
        } else {
            ProgressView("Reading EPUB…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Book preview

    private func bookPreview(_ book: EpubTextParser.ParsedBook) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Cover / icon
                    if let coverData = book.coverData,
                       let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 120, height: 120)
                            .overlay(Image(systemName: "book.closed")
                                .font(.system(size: 48)).foregroundStyle(.tertiary))
                    }

                    // Metadata
                    VStack(spacing: 4) {
                        Text(book.title).font(.title3.bold()).multilineTextAlignment(.center)
                        Text(book.author).foregroundStyle(.secondary)
                        Text("\(book.chapters.count) chapters · \(book.chapters.flatMap(\.paragraphs).count) paragraphs")
                            .font(.caption).foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Voice picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice").font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(voices) { voice in
                                VoiceCard(voice: voice, isSelected: selectedVoice == voice)
                                    .onTapGesture { selectedVoice = voice }
                            }
                        }
                    }
                }
                .padding(24)
            }

            // Generate button
            Button(action: startGeneration) {
                Label("Generate & Play", systemImage: "waveform")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    // MARK: - Error state

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Couldn't Read EPUB").font(.headline)
            Text(msg).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func parseEPUB() async {
        do { parsedBook = try EpubTextParser.parse(epubURL: epubURL) }
        catch { parseError = error.localizedDescription }
    }

    private func startGeneration() {
        switch supertonicService.modelState {
        case .notDownloaded, .error:
            showModelDownload = true
        case .loading, .downloading:
            // Model is in progress — show download sheet which auto-starts when ready
            showModelDownload = true
        case .ready:
            dismiss()
            generationService.generate(epubURL: epubURL, voice: selectedVoice)
        }
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
