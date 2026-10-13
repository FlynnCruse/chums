import AVFoundation

/// Push-to-talk capture: 16 kHz mono AAC, the smallest file Whisper still reads well.
final class Recorder {
    private var recorder: AVAudioRecorder?
    /// Simulator captures (-fakeVoice YES): no microphone at all (the Simulator stalls seconds reopening it), just an
    /// empty clip as long as the hold; the stand-in hub doesn't listen to it.
    static var fake = false
    private var fakeClip: (url: URL, start: Date)?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func start() throws {
        if Self.fake {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("utterance-\(UUID().uuidString).m4a")
            try Data().write(to: url); fakeClip = (url, Date()); return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("utterance-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else { throw NSError(domain: "Chums", code: 1) }
        recorder = r
    }

    /// Voice level 0…1 from the input meter, for the character to pulse with.
    var level: Double? {
        guard let r = recorder, r.isRecording else { return nil }
        r.updateMeters()
        let db = Double(r.averagePower(forChannel: 0))            // −160 … 0 dBFS
        return min(1, max(0, (db + 50) / 40))
    }

    /// Returns the file and how long it ran; nil if nothing was recording.
    func stop() -> (url: URL, seconds: TimeInterval)? {
        if let f = fakeClip { fakeClip = nil; return (f.url, Date().timeIntervalSince(f.start)) }
        guard let r = recorder else { return nil }
        let seconds = r.currentTime
        r.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)   // the mic is off between holds
        return (r.url, seconds)
    }
}

/// Speaks replies through the watch speaker (or AirPods when connected).
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    var onFinish: (() -> Void)?
    override init() { super.init(); synth.delegate = self }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.onFinish?() } }
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { DispatchQueue.main.async { self.onFinish?() } }

    /// Plays a reply's voice rendered on the Mac; false if it can't, so the caller falls back to `speak`.
    func play(_ data: Data) -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        synth.stopSpeaking(at: .immediate); player?.stop()
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        p.delegate = self; player = p
        return p.play()
    }

    func speak(_ text: String, voice id: String? = nil) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(id ?? UserDefaults.standard.string(forKey: "watchVoice"))
        u.rate = 0.52
        synth.stopSpeaking(at: .immediate); player?.stop()
        synth.speak(u)
    }

    /// The watch voice chosen in Settings (Watch voice), else the system's US English one.
    static func voice(_ id: String?) -> AVSpeechSynthesisVoice? {
        id.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// The English voices installed on the watch, best first (premium, enhanced, then default), novelty voices left out.
    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }
    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality { case .premium: return "Premium"; case .enhanced: return "Enhanced"; default: return "Default" }
    }

    func stop() { synth.stopSpeaking(at: .immediate); player?.stop(); player = nil }
}
