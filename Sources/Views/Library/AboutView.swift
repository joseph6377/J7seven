import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag grabber is handled by presentationDragIndicator
            
            // Clean close button header
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.primary.opacity(0.12))
                        .hoverEffect()
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Logo Image
                    AppLogoView()
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                        .padding(.top, 4)
                    
                    // Title and Version
                    VStack(spacing: 4) {
                        Text("About LysnBox")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                        
                        Text("VERSION 1.0")
                            .font(.j7Caption2Bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                            .kerning(1.2)
                    }
                    
                    // Decorative line
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 32, height: 1.5)
                        .padding(.vertical, 2)

                    // Editorial copy block
                    VStack(spacing: 10) {
                        Text("LysnBox began as a personal project to make books easier to enjoy through listening.")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(.primary.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2.5)
                        
                        Text("Today it’s open source and built in public.")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(.primary.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2.5)
                        
                        Text("Thank you for trying it.")
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundStyle(Color.accentColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 1)
                        
                        VStack(spacing: 4) {
                            Text("DESIGNED & DEVELOPED BY")
                                .font(.j7Caption2Bold)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .kerning(1.2)
                            
                            Text("Joseph Thekkekara")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundStyle(.secondary)
                            
                            Link("books.josepht.in", destination: URL(string: "https://books.josepht.in/")!)
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 2)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 16)
            }
        }
        .presentationDragIndicator(.visible)
    }
}
