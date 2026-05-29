import SwiftUI

struct PasteTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var title: String = ""
    @State private var text: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    let onImported: (SavedDocument) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Title (optional)") {
                    TextField("Untitled", text: $title)
                        .textInputAutocapitalization(.words)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            Spacer()
                            
                            Button {
                                if let pasted = UIPasteboard.general.string {
                                    text = pasted
                                }
                            } label: {
                                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.accentColor)
                        }
                        
                        TextEditor(text: $text)
                            .frame(minHeight: 280)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listen") {
                        Task {
                            await importNow()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.15)
                            .ignoresSafeArea()
                        
                        ProgressView("Preparing…")
                            .padding(20)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                    }
                }
            }
        }
    }
    
    private func importNow() async {
        isImporting = true
        errorMessage = nil
        
        do {
            let parsed = try await PastedTextImporter.importText(text, title: title)
            
            let doc = SavedDocument(
                id: UUID(),
                title: parsed.title,
                author: nil,
                coverImageData: nil,
                importedAt: Date(),
                lastOpenedAt: Date(),
                chapters: [
                    ChapterText(index: 0, title: "Pasted Text", paragraphs: parsed.paragraphs)
                ],
                cursor: PlaybackCursor(),
                sourceFormat: .pastedText,
                pageCount: nil,
                sourceURL: nil
            )
            
            appState.libraryService.saveDocument(doc)
            appState.refresh()
            onImported(doc)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}
