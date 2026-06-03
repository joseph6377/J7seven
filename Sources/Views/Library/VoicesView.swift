import SwiftUI
import AVFoundation
import Accelerate

struct VoicesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var samplePlayer = VoiceSamplePlayer()
    @State private var showModelDownload = false
    @State private var showEngineInfo = false
    @AppStorage("tts.defaultSteps") private var defaultSteps = 8

    let isLocked: Bool
    let showDoneButton: Bool
    @State private var selectedLanguage: String = "en"

    init(isLocked: Bool = false, showDoneButton: Bool = true) {
        self.isLocked = isLocked
        self.showDoneButton = showDoneButton
    }

    private var supertonicVoices: [TTSVoice] { TTSVoice.loadAll() }
    private var appleVoices: [TTSVoice] { appState.appleVoiceScheduler.cachedVoices }

    private var availableLanguages: [String] {
        ["en", "es", "fr", "de", "ja", "ko", "it", "pt"]
    }

    private var filteredSupertonicVoices: [TTSVoice] {
        supertonicVoices.filter { $0.language == selectedLanguage }
    }

    private var filteredAppleVoices: [TTSVoice] {
        appleVoices.filter { $0.language == selectedLanguage }
    }

    private func languageDisplayName(for code: String) -> String {
        let locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        if let name = locale.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        return code.uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Subtle Inline Subtitle
                    Text("Select your preferred narrator for studio-quality, offline playback.")
                        .font(.j7Body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    
                    // Dynamic Language Filter Pill Bar
                    if !isLocked && availableLanguages.count > 1 {
                        languageFilterBar
                    }
                    
                    if isSupertonicReady() {
                        // Synthesis Quality Picker
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

                            Picker("Synthesis Quality", selection: $defaultSteps) {
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
                        .padding(.horizontal, 16)

                        // Supertonic AI Voices Section
                        if !filteredSupertonicVoices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .bottom) {
                                    Text("Narrator Studio")
                                        .font(.j7Title3Serif)
                                    Spacer()
                                    Text("AI On-Device")
                                        .font(.j7Caption2Bold)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                                }
                                .padding(.horizontal, 16)
                                
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredSupertonicVoices) { voice in
                                        AcousticVoiceCard(
                                            voice: voice,
                                            isActive: isVoiceActive(voice),
                                            isPlaying: samplePlayer.playingVoiceId == voice.id,
                                            isPremium: true,
                                            onPlayToggle: {
                                                playPreview(for: voice)
                                            },
                                            onSelect: {
                                                selectVoice(voice)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    } else {
                        // Apple System Voices Section
                        if !filteredAppleVoices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("System Classics")
                                    .font(.j7Title3Serif)
                                    .padding(.horizontal, 16)
                                
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredAppleVoices) { voice in
                                        AcousticVoiceCard(
                                            voice: voice,
                                            isActive: isVoiceActive(voice),
                                            isPlaying: samplePlayer.playingVoiceId == voice.id,
                                            isPremium: false,
                                            onPlayToggle: {
                                                playPreview(for: voice)
                                            },
                                            onSelect: {
                                                selectVoice(voice)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120) // Cushion for floating bottom player deck
            }
            .background(Color.j7AppBackground.ignoresSafeArea())
            .navigationTitle("Voices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showEngineInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .imageScale(.large)
                    }
                }
            }
            .onDisappear {
                samplePlayer.stop()
            }
            .sheet(isPresented: $showEngineInfo) {
                EngineInfoSheet()
                    .preferredColorScheme(.light)
            }
            .sheet(isPresented: $showModelDownload) {
                ModelDownloadView(
                    synthesizer: appState.supertonicSynthesizer,
                    onReady: {}
                )
                .preferredColorScheme(.light)
            }
            .onAppear {
                if let activeSession = appState.activeSession {
                    // 1. Detect the book's dominant language
                    let bookLang = activeSession.document.detectedLanguage
                    
                    // 2. If it's supported by our 8 major languages, select it!
                    if availableLanguages.contains(bookLang) {
                        selectedLanguage = bookLang
                    } else {
                        // Fall back to active voice's language
                        selectedLanguage = activeSession.voice.language
                    }
                } else {
                    let activeVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId") ?? "M1-en"
                    if let matched = supertonicVoices.first(where: { $0.id == activeVoiceId }) {
                        selectedLanguage = matched.language
                    } else if activeVoiceId.contains("-"), let lang = activeVoiceId.split(separator: "-").last {
                        selectedLanguage = String(lang)
                    } else {
                        selectedLanguage = "en"
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var languageFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Individual Language Pills
                ForEach(availableLanguages, id: \.self) { lang in
                    Button {
                        selectedLanguage = lang
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(languageDisplayName(for: lang))
                            .font(.j7Caption)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                selectedLanguage == lang ? Color.primary : Color.primary.opacity(0.04)
                            )
                            .foregroundStyle(
                                selectedLanguage == lang ? Color.j7Surface : .secondary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helper Methods

    private func isVoiceActive(_ voice: TTSVoice) -> Bool {
        if let activeSession = appState.activeSession {
            return activeSession.voice.id == voice.id
        } else {
            let savedVoiceId = UserDefaults.standard.string(forKey: "tts.defaultVoiceId") ?? "M1-en"
            let normalizedSaved = savedVoiceId.contains("-") ? savedVoiceId : "\(savedVoiceId)-en"
            return voice.id == normalizedSaved
        }
    }

    private func selectVoice(_ voice: TTSVoice) {
        // Automatically synchronize active engine with selected voice type
        let isApple = voice.id.hasPrefix("apple-")
        appState.selectedEngine = isApple ? .apple : .supertonic

        if let activeSession = appState.activeSession {
            activeSession.setVoice(voice)
        }
        UserDefaults.standard.set(voice.id, forKey: "tts.defaultVoiceId")
        UserDefaults.standard.set(voice.id, forKey: "tts.defaultVoiceId.\(voice.language)")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func playPreview(for voice: TTSVoice) {
        if !voice.id.hasPrefix("apple-") && !isSupertonicReady() {
            showModelDownload = true
        } else {
            samplePlayer.playSample(
                for: voice,
                synthesizer: appState.supertonicSynthesizer,
                activeSession: appState.activeSession,
                steps: defaultSteps
            )
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func isSupertonicReady() -> Bool {
        if case .ready = appState.supertonicSynthesizer.modelState {
            return true
        }
        return false
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

// MARK: - Engine Info Sheet Component

struct EngineInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Supertonic 3")
                            .font(.j7Title1Serif)
                        Text("Offline Synthesis • Neural Engine")
                            .font(.j7SubheadlineBold)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
                
                Divider()
                
                Text("Experience fully private, studio-quality audiobook narration. Each model is custom-trained to provide unique natural inflection, deep characterization, and high-fidelity vocal textures, synthesized dynamically on your Apple Neural Engine.")
                    .font(.j7BodySerif)
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("Narration Engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.35), .medium])
    }
}

// MARK: - Acoustic Card Component

struct AcousticVoiceCard: View {
    let voice: TTSVoice
    let isActive: Bool
    let isPlaying: Bool
    let isPremium: Bool
    let onPlayToggle: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(voice.name)
                            .font(.j7BodyBold)
                            .foregroundStyle(isActive ? Color.accentColor : .primary)
                        
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.j7Caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                
                Spacer()
                
                // Visualizer & play preview block
                HStack(spacing: 10) {
                    if isPlaying {
                        MicroWaveformVisualizer(isPlaying: true)
                    }
                    
                    Button(action: onPlayToggle) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.j7CaptionBold)
                            .foregroundStyle(Color.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(isPlaying ? 0.15 : 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.j7Surface)
            )
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? Color.primary.opacity(0.02) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isActive ? Color.primary.opacity(0.45) : Color.j7Border,
                        lineWidth: isActive ? 1.2 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Micro Waveform Visualizer

struct MicroWaveformVisualizer: View {
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                TimelineView(.animation) { timeline in
                    let value = isPlaying ? amplitude(for: index, at: timeline.date.timeIntervalSince1970) : 0.15
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPlaying ? Color.primary.opacity(0.85) : Color.primary.opacity(0.3))
                        .frame(width: 3, height: max(4, value * 24))
                }
            }
        }
        .frame(height: 24)
    }
    
    private func amplitude(for index: Int, at time: TimeInterval) -> CGFloat {
        let speeds = [8.0, 11.0, 7.0, 13.0, 9.0]
        let phase = Double(index) * 1.2
        let sine = sin(time * speeds[index % 5] + phase)
        let normalized = (sine + 1.0) / 2.0 // 0 to 1
        return CGFloat(0.2 + normalized * 0.8) // 0.2 to 1.0
    }
}

// MARK: - Voice Sample Player

// Audio Engine & SpeechSynthesizer manager that plays voice preview samples
@MainActor
@Observable
final class VoiceSamplePlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    
    // For model-generated voices:
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isEngineSetup = false
    private var synthesisTask: Task<Void, Never>?
    
    var playingVoiceId: String? = nil

    override init() {
        super.init()
        synth.delegate = self
    }

    private func getSampleText(for voice: TTSVoice) -> String {
        let baseId = voice.id.components(separatedBy: "-").first ?? voice.id
        let lang = voice.language
        
        switch lang {
        case "es":
            switch baseId {
            case "M1": return "¡Hola! Soy Mateo. Mi voz es profunda y resonante, diseñada para novelas de fantasía y biografías históricas."
            case "M2": return "¡Hola! Soy Santiago. Con una pronunciación clara y articulada, doy vida a los audiolibros de negocios y no ficción."
            case "M3": return "Hola, soy Alejandro. Ofrezco un tono narrativo cálido y atractivo, perfecto para guías de autoayuda y memorias."
            case "M4": return "¡Hola! Soy Sebastián. Mi ritmo enérgico es perfecto para mantenerte al límite en thrillers y aventuras de ciencia ficción."
            case "M5": return "Hola. Soy Javier. Mi narración suave y clásica es ideal para la literatura, el romance y los ensayos reflexivos."
            case "F1": return "¡Hola! Soy Valentina. Ofrezco un estilo de lectura elegante y expresivo, ideal para ficción moderna y misterio."
            case "F2": return "Hola. Soy Sofía. Mi estilo cálido y reconfortante es perfecto para escuchar antes de dormir y ficción juvenil."
            case "F3": return "¡Bienvenido! Soy Camila. Con un tono profesional y claro, hago que los libros educativos sean fáciles de seguir."
            case "F4": return "¡Hola! Soy Isabella. Mi tono brillante y alegre es maravilloso para historias infantiles y relatos ligeros."
            case "F5": return "Hola. Soy Valeria. Ofrezco un flujo narrativo suave y elegante, dando vida a la poesía, el drama y la prosa clásica."
            default: break
            }
        case "fr":
            switch baseId {
            case "M1": return "Bonjour! Je m'appelle Gabriel. Ma voix est profonde et résonnante, idéale pour les romans fantastiques et les biographies historiques."
            case "M2": return "Bonjour! Je suis Lucas. Avec une élocution claire et articulée, je donne vie aux livres de non-fiction et de business."
            case "M3": return "Salut, je suis Arthur. J'offre un ton narratif chaleureux et engageant, parfait pour le développement personnel et les mémoires."
            case "M4": return "Salut! Je suis Louis. Mon rythme énergétique est parfait pour vous tenir en haleine dans les thrillers et la science-fiction."
            case "M5": return "Bonjour. Je suis Hugo. Ma narration fluide et classique est idéale pour la littérature, la romance et les essais."
            case "F1": return "Bonjour! Je suis Emma. Je propose un style de lecture élégant et expressif, idéal pour la fiction moderne et les polars."
            case "F2": return "Bonjour. Je suis Chloé. Mon style chaleureux et réconfortant est parfait pour s'endormir et la fiction pour jeunes adultes."
            case "F3": return "Bienvenue! Je suis Manon. Avec un ton professionnel et précis, je rends les livres éducatifs faciles à suivre."
            case "F4": return "Salut! Je suis Léa. Mon ton enjoué et vivant est merveilleux pour les histoires d'enfants et les contes légers."
            case "F5": return "Bonjour. Je suis Inès. J'apporte un flux narratif doux et élégant, donnant vie à la poésie, au drame et à la prose classique."
            default: break
            }
        case "de":
            switch baseId {
            case "M1": return "Hallo! Ich bin Maximilian. Meine Stimme ist tief und resonant, ideal für Fantasy-Romane und historische Biografien."
            case "M2": return "Hallo! Ich bin Lukas. Mit einer klaren und präzisen Aussprache erwecke ich Sach- und Businessbücher zum Leben."
            case "M3": return "Hallo, ich bin Jonas. Ich biete einen warmen und einladenden Ton, perfekt für Ratgeber und Biografien."
            case "M4": return "Hey! Ich bin Finn. Mein energisches Tempo ist perfekt, um Sie bei Thrillern und Science-Fiction in Atem zu halten."
            case "M5": return "Hallo. Ich bin Elias. Meine sanfte und klassische Erzählweise ist maßgeschneidert für Literatur und Liebesromane."
            case "F1": return "Hallo! Ich bin Marie. Ich biete einen ausdrucksstarken Lesestil, ideal für moderne Belletristik und Krimis."
            case "F2": return "Hallo. Ich bin Sophie. Meine warme und beruhigende Art ist perfekt zum Einschlafen und für Jugendbücher."
            case "F3": return "Willkommen! Ich bin Charlotte. Mit einem klaren, professionellen Ton mache ich komplexe Sachbücher leicht verständlich."
            case "F4": return "Hallo! Ich bin Emilia. Mein fröhlicher Ton ist wunderbar für Kindergeschichten und humorvolle Erzählungen."
            case "F5": return "Hallo. Ich bin Mia. Ich liefere einen sanften Erzählfluss, der Poesie, Drama und klassische Prosa zum Leben erweckt."
            default: break
            }
        case "it":
            switch baseId {
            case "M1": return "Ciao! Sono Leonardo. La mia voce è profonda e risonante, ideale per romanzi fantasy e grandi biografie storiche."
            case "M2": return "Ciao! Sono Francesco. Con una pronuncia chiara e articolata, do vita ai libri di saggistica e business."
            case "M3": return "Ciao, sono Alessandro. Offro un tono caldo e vicino, perfetto per guide di self-help e biografie."
            case "M4": return "Ehi! Sono Lorenzo. Il mio ritmo energico è perfetto per tenerti con il fiato sospeso in thriller e fantascienza."
            case "M5": return "Ciao. Sono Mattia. La mia narrazione fluida e classica è ideale per letteratura, romanzi rosa e saggi."
            case "F1": return "Ciao! Sono Sofia. Offro uno stile di leitura elegante ed espressivo, ideale per narrativa moderna e gialli."
            case "F2": return "Ciao. Sono Aurora. Il mio stile caldo e rassicurante è perfetto per la buonanotte e la narrativa per ragazzi."
            case "F3": return "Benvenuti! Sono Giulia. Con un tono chiaro e professionale, rendo i libri educativi semplici da seguire."
            case "F4": return "Ciao! Sono Ginevra. Il mio tono allegro e vivace è splendido per storie per bambini e racconti leggeri."
            case "F5": return "Ciao. Sono Beatrice. Offro un flusso narrativo morbido ed elegante, dando vita a poesia, dramma e prosa classica."
            default: break
            }
        case "pt":
            switch baseId {
            case "M1": return "Olá! Eu sou o Miguel. Minha voz é profunda e ressonante, ideal para romances de fantasia e biografias históricas."
            case "M2": return "Olá! Eu sou o Arthur. Com uma pronúncia clara e articulada, dou vida a audiolivros de negócios e não ficção."
            case "M3": return "Olá, sou o Heitor. Ofereço um tom caloroso e envolvente, perfeito para guias de autoajuda e biografias."
            case "M4": return "Olá! Eu sou o Bernardo. Meu ritmo enérgico é perfeito para manter você ansioso em thrillers e ficção científica."
            case "M5": return "Olá. Eu sou o Davi. Minha narração clássica e suave é ideal para literatura, romance e ensaios reflexivos."
            case "F1": return "Olá! Eu sou a Helena. Ofereço um estilo de leitura elegante e expressivo, ideal para ficção moderna e mistério."
            case "F2": return "Olá. Eu sou a Alice. Meu estilo caloroso e confortante é perfeito para ouvir antes de dormir e ficção juvenil."
            case "F3": return "Boas-vindas! Eu sou a Laura. Com um tom profissional e claro, torno livros educativos fáceis de acompanhar."
            case "F4": return "Olá! Eu sou a Manuela. Meu tom brilhante e alegre é maravilhoso para histórias infantis e contos leves."
            case "F5": return "Olá. Eu sou a Isabella. Ofereço um fluxo narrativo suave e elegante, dando vida à poesia, drama e prosa clássica."
            default: break
            }
        case "ja":
            switch baseId {
            case "M1": return "こんにちは！ヒロトです。私の声は深く響き渡り、ファンタジー小説や歴史的な伝記に最適です。"
            case "M2": return "こんにちは、レンです。明瞭で聞き取りやすい語りで、ビジネス書やノンフィクションに命を吹き込みます。"
            case "M3": return "こんにちは、ユウトです。温かみのある魅力的な語り口で、自己啓発本や回顧録に最適です。"
            case "M4": return "やあ！ミナトです。エネルギッシュで切れ味の良いテンポは、スリラーやSF小説の緊張感を高めるのにぴったりです。"
            case "M5": return "こんにちは、ハルトです。滑らかでクラシックな語り口は、文芸作品やロマンス、省察的なエッセイに向いています。"
            case "F1": return "こんにちは！ヒマリです。洗練された表現力豊かな読み上げスタイルで、現代小説やミステリーに最適です。"
            case "F2": return "こんにちは、ツムギです。温かく心地よいナレーションは、お休み前の読書やヤングアダルト小説にぴったりです。"
            case "F3": return "ようこそ！アオイです。明瞭でプロフェッショナルなトーンで、専門書や教育的な内容も分かりやすくお届けします。"
            case "F4": return "こんにちは！イチカです。明るく生き生きとしたトーンは、児童書やコメディ、軽快な物語にぴったりです。"
            case "F5": return "こんにちは、メイです。優雅でしなやかな語りの流れで、詩やドラマ、古典的な散文を生き生きと表現します。"
            default: break
            }
        case "ko":
            switch baseId {
            case "M1": return "안녕하세요! 민준입니다. 제 목소리는 깊고 울림이 있어 판타지 소설과 역사 전기물에 어울립니다."
            case "M2": return "안녕하세요! 서준입니다. 명확하고 또박또박한 발음으로 경영 서적과 비소설 분야를 생생하게 낭독합니다."
            case "M3": return "안녕하세요, 도윤입니다. 따뜻하고 몰입감 있는 어조로 자기계발서와 회고록에 어울리는 목소리입니다."
            case "M4": return "안녕하세요! 유준입니다. 활기차고 경쾌한 호흡으로 스릴러와 공상과학 소설의 긴장감을 극대화합니다."
            case "M5": return "안녕하세요, 은우입니다. 부드럽고 클래식한 낭독으로 문학, 로맨스, 그리고 수필에 적합합니다."
            case "F1": return "안녕하세요! 서아입니다. 세련되고 표현력이 풍부한 낭독 스타일로 현대 소설과 추리물에 적합합니다."
            case "F2": return "안녕하세요, 지안입니다. 따뜻하고 포근한 음성으로 잠자리 독서와 청소년 소설에 잘 어울립니다."
            case "F3": return "환영합니다! 하윤입니다. 명료하고 전문적인 톤으로 어려운 교육 서적도 쉽게 이해할 수 있도록 도와드립니다."
            case "F4": return "안녕하세요! 서윤입니다. 밝고 생기 넘치는 목소리로 아동 도서와 유쾌한 이야기에 어울립니다."
            case "F5": return "안녕하세요, 지우입니다. 부드럽고 우아한 흐름으로 시와 희곡, 그리고 클래식 산문에 생명을 불어넣습니다."
            default: break
            }
        default:
            // English / Fallback
            switch baseId {
            case "M1": return "Hello! I am Marcus. My voice is deep and resonant, custom-crafted for epic fantasy novels and grand historical biographies."
            case "M2": return "Hello there! I am Nathan. With a clear and highly articulate delivery, I bring non-fiction and business audiobooks to life."
            case "M3": return "Hi, I'm Oliver. I provide a warm and engaging narrative tone, perfect for self-help guides, biographies, and memoirs."
            case "M4": return "Hey! I am Paul. My energetic and crisp pacing is perfect for keeping you on the edge of your seat during thrillers and sci-fi adventures."
            case "M5": return "Hello. I am Ryan. My smooth and classic narration is tailored for literature, romance, and reflective essays."
            case "F1": return "Hello! I am Alice. I offer a sleek and highly expressive reading style, ideal for modern fiction and mystery novels."
            case "F2": return "Hello there. I am Beth. My warm and comforting narration style is perfect for bedtime listening and young adult fiction."
            case "F3": return "Welcome! I am Claire. With a crisp, highly professional tone, I make complex educational and technical books easy to follow."
            case "F4": return "Hi! I am Diana. My bright and lively tone is wonderful for children's stories, comedy, and lighthearted tales."
            case "F5": return "Hello. I'm Eve. I deliver a soft, elegant narrative flow, bringing poetry, drama, and classic prose to life."
            default: break
            }
        }
        
        return "Hello! I am \(voice.name). This is a preview of my voice in the Books App. Do you like my pronunciation?"
    }

    func playSample(for voice: TTSVoice, synthesizer: SupertonicSynthesizer, activeSession: ReaderSession?, steps: Int = 8) {
        // 1. Check if we are already playing this exact voice
        let alreadyPlayingSelected = (playingVoiceId == voice.id)
        
        // Always stop any current audio immediately
        stop()
        
        if alreadyPlayingSelected {
            // Tapped on the same voice: stop was requested, so we're done
            return
        }

        // 2. Cancel the active book reader session to prevent overlapping speech
        activeSession?.pause()

        playingVoiceId = voice.id

        if voice.id.hasPrefix("apple-") {
            // Apple System Voice Playback
            let sampleText = getSampleText(for: voice)
            let utterance = AVSpeechUtterance(string: sampleText)
            let identifier = String(voice.id.dropFirst(6))
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        } else {
            // Premium Model-Generated Playback using actual Supertonic ONNX synthesizer
            let sampleText = getSampleText(for: voice)
            let stream = synthesizer.synthesize(sampleText, voice: voice, options: SynthOptions(steps: steps))
            
            synthesisTask = Task {
                do {
                    var samples = [Float]()
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        samples.append(contentsOf: chunk.samples)
                    }
                    
                    if Task.isCancelled { return }
                    
                    // Add subtle trailing silence for a natural transition
                    samples.append(contentsOf: [Float](repeating: 0.0, count: Int(0.075 * 44100)))
                    
                    guard let buffer = makePCMBuffer(from: samples) else {
                        playingVoiceId = nil
                        return
                    }
                    
                    setupPreviewEngine()
                    if !engine.isRunning {
                        try? engine.start()
                    }
                    
                    playerNode.play()
                    await playerNode.scheduleBuffer(buffer, at: nil, options: [])
                    if self.playingVoiceId == voice.id {
                        self.playingVoiceId = nil
                    }
                } catch {
                    print("[VoiceSamplePlayer] Preview synthesis error: \(error)")
                    playingVoiceId = nil
                }
            }
        }
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        synthesisTask?.cancel()
        synthesisTask = nil
        playerNode.stop()
        playingVoiceId = nil
    }

    private func setupPreviewEngine() {
        guard !isEngineSetup else { return }
        engine.attach(playerNode)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isEngineSetup = true
    }

    private func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }

        var peak: Float = 0.0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        let normalized: [Float]
        if peak > 0.001 {
            var scale = Float(0.85) / peak
            var result = [Float](repeating: 0, count: samples.count)
            vDSP_vsmul(samples, 1, &scale, &result, 1, vDSP_Length(samples.count))
            normalized = result
        } else {
            normalized = samples
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(normalized.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(normalized.count)
        normalized.withUnsafeBufferPointer { ptr in
            if let dest = buffer.floatChannelData?[0] {
                dest.update(from: ptr.baseAddress!, count: normalized.count)
            }
        }
        return buffer
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playingVoiceId = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playingVoiceId = nil
        }
    }
}
