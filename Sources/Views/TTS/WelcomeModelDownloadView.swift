import SwiftUI

struct WelcomeModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    let synthesizer: SupertonicSynthesizer
    var onReady: () -> Void = {}
    var onUseApple: () -> Void = {}

    @State private var hasTappedDownload = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header Block
                    VStack(spacing: 12) {
                        AppLogoView()
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
                            .padding(.top, 12)
                        
                        VStack(spacing: 4) {
                            Text("Welcome to LysnBox")
                                .font(.j7Title1Serif)
                                .foregroundStyle(.primary)
                            
                            Text("YOUR PRIVATE AUDIOBOOK SANCTUARY")
                                .font(.j7Caption2Bold)
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                        }
                        
                        Text("Configure your audio narration engine to begin. LysnBox operates 100% on-device, ensuring complete privacy.")
                            .font(.j7Subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 8)
                    
                    // Card Options Section
                    VStack(spacing: 16) {
                        // Option 1: Premium Supertonic 3 Neural Engine
                        supertonicCard
                        
                        // Option 2: Apple Native System Engine
                        appleNativeCard
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 36)
            }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: synthesizer.modelState) { _, newValue in
            if case .ready = newValue {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onReady()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Card Component - Supertonic
    private var supertonicCard: some View {
        let isDownloadingState = hasTappedDownload || isDownloading(synthesizer.modelState)
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Supertonic 3 Engine")
                            .font(.j7Title3Serif)
                            .foregroundStyle(.primary)
                        
                        Text("RECOMMENDED")
                            .font(.j7Caption2Bold)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    
                    Text("Studio-grade dynamic narration with deep inflection and rich characterization. Runs offline using your local Apple Neural Engine.")
                        .font(.j7CaptionSerifBold)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                Spacer()
            }
            
            Divider()
                .background(Color.primary.opacity(0.06))
            
            // Dynamic State-based UI inside the card
            progressOrActionButton(isDownloadingState)
        }
        .padding(.all, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.02))
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    hasTappedDownload ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06),
                    lineWidth: hasTappedDownload ? 1.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(0.01), radius: 8, x: 0, y: 4)
    }

    // MARK: - Card Component - Apple Native
    private var appleNativeCard: some View {
        let isDownloadingState = hasTappedDownload || isDownloading(synthesizer.modelState)
        
        return Button {
            guard !isDownloadingState else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onUseApple()
            dismiss()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("System Classics")
                            .font(.j7Title3Serif)
                            .foregroundStyle(isDownloadingState ? .secondary : .primary)
                        
                        Text("LIGHTWEIGHT")
                            .font(.j7Caption2Bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    
                    Text("Standard offline speech using Apple's built-in system voices. Extremely lightweight and ready to start immediately.")
                        .font(.j7CaptionSerifBold)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.j7SubheadlineBold)
                    .foregroundStyle(isDownloadingState ? Color.primary.opacity(0.12) : Color.primary.opacity(0.25))
            }
            .padding(.all, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.02))
            )
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDownloadingState)
        .opacity(isDownloadingState ? 0.5 : 1.0)
    }

    // MARK: - Dynamic Controls Block
    @ViewBuilder
    private func progressOrActionButton(_ isDownloadingState: Bool) -> some View {
        switch synthesizer.modelState {
        case .notDownloaded:
            if !hasTappedDownload {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    hasTappedDownload = true
                    Task {
                        try? await synthesizer.downloadModel()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Download Premium Engine (~350 MB)", systemImage: "arrow.down.circle.fill")
                            .font(.j7SubheadlineBold)
                            .foregroundStyle(.white)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: Color.accentColor.opacity(0.2), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView("Initiating download...")
                    .font(.j7Caption)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            
        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(.accentColor)
                
                HStack {
                    Text("Downloading premium neural voices...")
                        .font(.j7Caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.j7CaptionBold)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.accentColor)
                Text("Preparing voice studio...")
                    .font(.j7Caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            
        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.j7Title3)
                Text("Model Ready! Setting up your sanctuary...")
                    .font(.j7CaptionBold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            
        case .error(let errorMsg):
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Download failed")
                        .font(.j7CaptionBold)
                        .foregroundStyle(.red)
                }
                
                Text(errorMsg)
                    .font(.j7Caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        try? await synthesizer.downloadModel()
                    }
                } label: {
                    Text("Retry Download")
                        .font(.j7CaptionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helper Methods
    private func isDownloading(_ state: ModelState) -> Bool {
        if case .downloading = state { return true }
        if case .loading = state { return true }
        return false
    }
}
