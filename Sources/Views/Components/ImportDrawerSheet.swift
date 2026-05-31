import SwiftUI

struct ImportDrawerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    
    // Callback actions triggered when a row is selected
    let onSelectFile: () -> Void
    let onSelectURL: () -> Void
    let onSelectPasteText: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add to Library")
                .font(.j7Title3Serif)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.top, 24) // Elegant vertical spacing below native drag indicator
            
            VStack(spacing: 0) {
                drawerRow(
                    title: "From File",
                    subtitle: "Import EPUB or PDF files",
                    icon: "doc",
                    action: onSelectFile
                )
                
                Divider()
                    .padding(.leading, 56)
                    .background(Color.primary.opacity(0.03))
                
                drawerRow(
                    title: "From URL",
                    subtitle: "Convert any web article to audio",
                    icon: "link",
                    action: onSelectURL
                )
                
                Divider()
                    .padding(.leading, 56)
                    .background(Color.primary.opacity(0.03))
                
                drawerRow(
                    title: "Paste Text",
                    subtitle: "Paste text and start listening",
                    icon: "doc.on.clipboard",
                    action: onSelectPasteText
                )
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
    }
    
    private func drawerRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            // Delay action slightly to allow drawer dismissal transition to start smoothly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                action()
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.j7BodyBold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
