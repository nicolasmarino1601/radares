import AVFoundation

/// Voz y pitidos. Usa la sesión de audio de "indicaciones de navegación": baja el volumen de la
/// música o del navegador mientras habla y suena por el Bluetooth o CarPlay del auto, también con
/// el teléfono bloqueado.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var enabled = true
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var configured = false
    private var beepCache: [Int: Data] = [:]
    private lazy var voice: AVSpeechSynthesisVoice? = Speaker.pickVoice()

    override init() {
        super.init()
        synth.delegate = self
    }

    private static func pickVoice() -> AVSpeechSynthesisVoice? {
        let es = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "es-ES" }
        if let best = es.max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        return AVSpeechSynthesisVoice(language: "es-ES")
    }

    func prepare() {
        guard !configured else { return }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            try? s.setCategory(.playback, options: [.duckOthers])
        }
        configured = true
    }

    func say(_ text: String, beeps: Int) {
        guard enabled else { return }
        prepare()
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let n = max(1, min(3, beeps))
        playBeeps(n)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.05)
        u.preUtteranceDelay = 0.22 * Double(n) + 0.05
        synth.speak(u)
    }

    private func playBeeps(_ n: Int) {
        let data: Data
        if let d = beepCache[n] {
            data = d
        } else {
            data = Speaker.beepWav(count: n)
            beepCache[n] = data
        }
        player = try? AVAudioPlayer(data: data)
        player?.volume = 0.8
        player?.play()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        scheduleDeactivate()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        scheduleDeactivate()
    }

    /// Devuelve el volumen a la música o al navegador cuando termina de hablar.
    private func scheduleDeactivate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, !self.synth.isSpeaking, !(self.player?.isPlaying ?? false) else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Pitidos de 880 Hz en un WAV en memoria.
    static func beepWav(count: Int) -> Data {
        let sr = 22_050
        let gap = Int(Double(sr) * 0.22), len = Int(Double(sr) * 0.16)
        let total = gap * count
        var samples = [Int16](repeating: 0, count: total)
        for k in 0..<count {
            let start = gap * k
            for i in 0..<len where start + i < total {
                let t = Double(i) / Double(sr)
                let attack = min(1, t / 0.02)
                let release = max(0, 1 - max(0, t - 0.02) / 0.14)
                let v = sin(2 * Double.pi * 880 * t) * attack * release * 0.5
                samples[start + i] = Int16(v * 32_767)
            }
        }
        var d = Data()
        func put(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put("RIFF"); u32(UInt32(36 + total * 2)); put("WAVE")
        put("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        put("data"); u32(UInt32(total * 2))
        for s in samples { u16(UInt16(bitPattern: s)) }
        return d
    }
}
