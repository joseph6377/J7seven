import SwiftUI

struct ImportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    
    let onUploadTap: () -> Void
    let onURLTap: () -> Void
    let onWriteTextTap: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(Color.primary)
                        
                        Text("Add documents, web articles, or raw text to your reading sanctuary.")
                            .font(.j7Body)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Main layout cards
                    VStack(spacing: 20) {
                        // 1. Upload a File (Prominent, full-width card)
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onUploadTap()
                        }) {
                            VStack(spacing: 16) {
                                Spacer()
                                
                                // Large premium Icon container
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.08))
                                        .frame(width: 72, height: 72)
                                    
                                    Image(systemName: "doc.badge.plus")
                                        .font(.title)
                                        .foregroundStyle(Color.accentColor)
                                }
                                
                                VStack(spacing: 4) {
                                    Text("Upload a file")
                                        .font(.j7Title3Serif)
                                        .foregroundStyle(Color.primary)
                                    
                                    Text("Import EPUB, PDF, or DRM-free document formats")
                                        .font(.j7Caption)
                                        .foregroundStyle(Color.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .background(Color.j7Surface)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.j7Border, lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.03), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(PremiumCardButtonStyle())
                        
                        // 2. Paste a Link & Write Text (Side-by-side cards)
                        HStack(spacing: 16) {
                            // Paste a Link Card
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onURLTap()
                            }) {
                                VStack(spacing: 16) {
                                    Spacer()
                                    
                                    ZStack {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.08))
                                            .frame(width: 56, height: 56)
                                        
                                        Image(systemName: "globe")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    
                                    VStack(spacing: 4) {
                                        Text("Paste a link")
                                            .font(.j7BodyBold)
                                            .foregroundStyle(Color.primary)
                                        
                                        Text("Convert any web article or news URL into clean audio")
                                            .font(.j7Caption)
                                            .foregroundStyle(Color.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 8)
                                    }
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 175)
                                .background(Color.j7Surface)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.j7Border, lineWidth: 1.5)
                                )
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.03), radius: 10, x: 0, y: 5)
                            }
                            .buttonStyle(PremiumCardButtonStyle())
                            
                            // Write Text Card
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onWriteTextTap()
                            }) {
                                VStack(spacing: 16) {
                                    Spacer()
                                    
                                    ZStack {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.08))
                                            .frame(width: 56, height: 56)
                                        
                                        Image(systemName: "square.and.pencil")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    
                                    VStack(spacing: 4) {
                                        Text("Write text")
                                            .font(.j7BodyBold)
                                            .foregroundStyle(Color.primary)
                                        
                                        Text("Paste direct content, drafts, or notes and start reading")
                                            .font(.j7Caption)
                                            .foregroundStyle(Color.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 8)
                                    }
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 175)
                                .background(Color.j7Surface)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.j7Border, lineWidth: 1.5)
                                )
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.03), radius: 10, x: 0, y: 5)
                            }
                            .buttonStyle(PremiumCardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer(minLength: 120) // Provide breathing room for tab bar & miniplayer
                }
            }
            .background(Color.j7AppBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("") // Keep header clean without duplicating the large title
                }
            }
        }
    }
}

// MARK: - Tap Animation
struct PremiumCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
