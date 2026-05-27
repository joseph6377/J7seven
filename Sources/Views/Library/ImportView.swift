import SwiftUI

struct ImportView: View {
    @Environment(AppState.self) private var appState
    let onUploadTap: () -> Void

    @AppStorage("tts.defaultSteps") private var defaultSteps = 8
    @State private var animatePortal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                // Ultra-Minimalist Synthesis Portal
                synthesisPortal
                
                Spacer()
                
                // Integrated Settings & Stats Card (Sleek and unified)
                VStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Synthesis Quality")
                                .font(.j7SubheadlineSerifBold)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(qualityName(for: defaultSteps))
                                .font(.j7CaptionBold)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 4)
                        
                        Picker("Steps", selection: $defaultSteps) {
                            Text("Balanced").tag(5)
                            Text("High").tag(8)
                            Text("Ultra").tag(12)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: defaultSteps) { _, newValue in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            appState.activeSession?.setSteps(newValue)
                        }
                    }
                    
                    Divider()
                        .opacity(0.4)
                    
                    // Premium minimal parameters row
                    HStack(spacing: 0) {
                        minimalStat(title: "ENGINE", value: "Supertonic 3")
                        Spacer()
                        minimalStat(title: "MODEL", value: "~66M local")
                        Spacer()
                        minimalStat(title: "PRIVACY", value: "Offline")
                    }
                }
                .padding(22)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 120) // Spacing for mini player and tab bar
            }
            .navigationTitle("Import Hub")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var synthesisPortal: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onUploadTap()
        } label: {
            VStack(spacing: 24) {
                ZStack {
                    // Fine, single elegant pulsing ring
                    Circle()
                        .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
                        .frame(width: 160, height: 160)
                        .scaleEffect(animatePortal ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: animatePortal)
                    
                    // Main glass-like circle
                    Circle()
                        .fill(Color.primary.opacity(0.015))
                        .frame(width: 120, height: 120)
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        }
                        .shadow(color: Color.accentColor.opacity(0.03), radius: 8)
                    
                    // Fine line interactive vector icon
                    Image(systemName: "plus")
                        .font(.j7TitleLarge)
                        .foregroundStyle(Color.accentColor)
                }
                
                VStack(spacing: 6) {
                    Text("Add Book")
                        .font(.j7Title3Serif)
                        .foregroundStyle(.primary)
                    Text("Select an EPUB to generate speech")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            animatePortal = true
        }
    }

    private func minimalStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.j7Caption2Bold)
                .foregroundStyle(.secondary)
                .kerning(1.0)
            Text(value)
                .font(.j7SubheadlineSerifBold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func qualityName(for steps: Int) -> String {
        switch steps {
        case 5: return "Balanced"
        case 8: return "High"
        case 12: return "Ultra"
        default: return "High"
        }
    }
}
