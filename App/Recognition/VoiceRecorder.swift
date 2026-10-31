import Foundation
import Combine
import Speech
import AVFoundation

enum VoicePermission { case authorized, denied, restricted }
enum VoiceActivity { case active, inactive, background }

@MainActor
protocol VoiceRecordingClient: AnyObject {
    var supportsOnDeviceRecognition: Bool { get }
    var isAvailable: Bool { get }
    func speechPermission() async -> VoicePermission
    func microphonePermission() async -> Bool
    func configure(hints: [String])
    func start(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
               interrupted: @escaping @MainActor () -> Void) throws
    func restart(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
                 interrupted: @escaping @MainActor () -> Void) throws
    func stop()
    func cancel()
}

extension VoiceRecordingClient {
    func configure(hints: [String]) {}
    func restart(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
                 interrupted: @escaping @MainActor () -> Void) throws {
        cancel()
        try start(result: result, interrupted: interrupted)
    }
}

private final class SpeechRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
    func replace(with next: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = next
    }
    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
    }
}

/// Some on-device recognizers return only the newest utterance without isFinal.
/// Keep non-overlapping audio windows, while allowing revisions within one window.
@MainActor
final class VoiceTranscriptAccumulator {
    struct AudioRange {
        let start: TimeInterval
        let end: TimeInterval
    }
    private struct Utterance {
        let text: String
        let range: AudioRange?
    }
    private var completed: [Utterance] = []
    private var current = Utterance(text: "", range: nil)
    private var receivedAt: TimeInterval?

    func update(_ text: String, range: AudioRange?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return transcript }
        let previousKey = key(current.text), nextKey = key(next)
        let continuous = nextKey.hasPrefix(previousKey) || previousKey.hasPrefix(nextKey)
        // A later cumulative result may include previously retained utterances again.
        let includesEarlierAudio: Bool
        if let first = completed.first, let earlierRange = first.range, let range {
            includesEarlierAudio = range.start <= earlierRange.start + 0.1
                && nextKey.hasPrefix(key(first.text)) && nextKey.count > key(first.text).count
        } else if let first = completed.first {
            includesEarlierAudio = nextKey.hasPrefix(key(first.text)) && nextKey.contains(previousKey)
                && nextKey.count > key(first.text).count
        } else { includesEarlierAudio = false }
        if includesEarlierAudio {
            completed.removeAll()
        } else if !current.text.isEmpty && !continuous {
            let laterAudio = range.flatMap { next in current.range.map { next.start >= $0.end - 0.05 && next.start > $0.start + 0.25 } } ?? false
            // Timing may be absent in early partial results. Only separate unrelated
            // phrases after a pause; ordinary kanji/quantity revisions still replace.
            let timingUnavailableOrReset = range == nil || current.range == nil
                || (range.flatMap { next in current.range.map { next.start <= $0.start + 0.1 } } ?? false)
            let pauseWithoutTiming = timingUnavailableOrReset
                && receivedAt.map { now - $0 >= 1.0 } == true
                && nextKey.count >= 2 && previousKey.count >= 2
                && !sharesPair(previousKey, nextKey)
            if laterAudio || pauseWithoutTiming { completed.append(current) }
        }
        if next != current.text { receivedAt = now }
        current = Utterance(text: next, range: range)
        return transcript
    }
    private var transcript: String {
        String((completed.map(\.text) + [current.text]).filter { !$0.isEmpty }.joined(separator: "\n").prefix(4000))
    }
    private func key(_ text: String) -> String {
        text.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
    private func sharesPair(_ first: String, _ second: String) -> Bool {
        let characters = Array(first)
        guard characters.count >= 2 else { return false }
        return (0..<(characters.count - 1)).contains { second.contains(String(characters[$0...($0 + 1)])) }
    }
}

@MainActor
private final class SystemVoiceRecordingClient: VoiceRecordingClient {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let requestBox = SpeechRequestBox()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var interruption: NSObjectProtocol?
    private var tapInstalled = false
    private var sessionActive = false
    private var hints: [String] = []
    func configure(hints: [String]) { self.hints = Array(hints.prefix(100)) }
    var supportsOnDeviceRecognition: Bool { recognizer?.supportsOnDeviceRecognition == true }
    var isAvailable: Bool { recognizer?.isAvailable == true }

    func speechPermission() async -> VoicePermission {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        default: return .restricted
        }
    }
    func microphonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
    func start(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
               interrupted: @escaping @MainActor () -> Void) throws {
        guard recognizer != nil, supportsOnDeviceRecognition, isAvailable else {
            throw CocoaError(.featureUnsupported)
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true); sessionActive = true
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            try beginRecognition(result: result)
            let requestBox = self.requestBox
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in requestBox.append(buffer) }
            tapInstalled = true
            interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                object: session, queue: .main) { notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
                Task { @MainActor in interrupted() }
            }
            engine.prepare(); try engine.start()
        } catch { cancel(); throw error }
    }
    func restart(result: @escaping @MainActor (String?, Bool, Bool) -> Void,
                 interrupted: @escaping @MainActor () -> Void) throws {
        guard engine.isRunning, sessionActive else { throw CocoaError(.featureUnsupported) }
        recognitionTask?.cancel(); recognitionTask = nil
        try beginRecognition(result: result)
    }
    private func beginRecognition(result: @escaping @MainActor (String?, Bool, Bool) -> Void) throws {
        guard let recognizer, supportsOnDeviceRecognition, isAvailable else { throw CocoaError(.featureUnsupported) }
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.requiresOnDeviceRecognition = true; next.shouldReportPartialResults = true
        next.taskHint = .dictation; next.contextualStrings = hints
        requestBox.replace(with: next)
        let accumulator = VoiceTranscriptAccumulator()
        recognitionTask = recognizer.recognitionTask(with: next) { response, error in
            let text = response?.bestTranscription.formattedString
            let segments = response?.bestTranscription.segments ?? []
            let start = segments.first?.timestamp ?? 0
            let end = segments.map { $0.timestamp + $0.duration }.max() ?? 0
            let range = end > start ? VoiceTranscriptAccumulator.AudioRange(start: start, end: end) : nil
            let final = response?.isFinal ?? false, failed = error != nil
            Task { @MainActor in
                result(text.map { accumulator.update($0, range: range) }, final, failed)
            }
        }
    }
    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        requestBox.endAudio()
    }
    func cancel() {
        stop(); recognitionTask?.cancel(); recognitionTask = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption); self.interruption = nil }
    }
}

@MainActor
final class VoiceRecorder: ObservableObject {
    enum Phase { case idle, permissions, waitingForActive, recording, finishing }
    @Published private(set) var transcript = ""
    @Published private(set) var phase = Phase.idle
    @Published private(set) var message: String?
    @Published private(set) var settingsNeeded = false
    var busy: Bool { phase != .idle }
    var recording: Bool { phase == .recording }
    var progressText: String {
        switch phase {
        case .permissions: return "マイク・音声認識の許可を確認しています…"
        case .waitingForActive: return "アプリに戻ると録音を開始します…"
        case .recording: return "聞き取っています…"
        case .finishing: return "文章を確定しています…"
        case .idle: return ""
        }
    }
    var buttonText: String {
        switch phase {
        case .idle: return "録音を開始（30秒まで）"
        case .permissions: return "許可の確認を中止"
        case .waitingForActive: return "録音を中止"
        case .recording: return "録音を終了"
        case .finishing: return "認識を中止"
        }
    }
    private let client: any VoiceRecordingClient
    private let recordingLimit: Duration
    private let finishingLimit: Duration
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var segment = UUID()
    private var completedText = ""
    private var activity = VoiceActivity.active
    private var activation: CheckedContinuation<Bool, Never>?

    init(client: (any VoiceRecordingClient)? = nil,
         recordingLimit: Duration = .seconds(30), finishingLimit: Duration = .seconds(3)) {
        self.client = client ?? SystemVoiceRecordingClient()
        self.recordingLimit = recordingLimit; self.finishingLimit = finishingLimit
    }

    func activityChanged(_ activity: VoiceActivity) {
        self.activity = activity
        switch activity {
        case .active:
            let pending = activation; activation = nil; pending?.resume(returning: true)
        case .inactive:
            // Permission dialogs temporarily deactivate the scene. Never start the mic until active again.
            if phase == .recording || phase == .finishing { cancel(message: stoppedMessage) }
        case .background:
            if busy { cancel(message: stoppedMessage) }
        }
    }
    private var stoppedMessage: String { "録音を停止しました。文章を確認するか手入力で続けてください。" }

    func start(hints: [String] = []) async {
        guard !busy else { return }
        guard activity == .active else { message = "アプリに戻ってから録音を開始してください。"; return }
        cancel(); message = nil; settingsNeeded = false; transcript = ""; completedText = ""; phase = .permissions
        let token = generation
        guard client.supportsOnDeviceRecognition else {
            finish(message: "端末内の日本語音声認識を利用できません。下の手入力を使ってください。", token: token); return
        }
        let authorization = await client.speechPermission()
        guard token == generation else { return }
        guard authorization == .authorized else {
            settingsNeeded = authorization == .denied
            finish(message: "音声認識が許可されていません。手入力するか、iPhoneの設定を確認してください。", token: token); return
        }
        guard await waitForActive(token: token), token == generation else { return }
        phase = .permissions
        let microphone = await client.microphonePermission()
        guard token == generation else { return }
        guard microphone else {
            settingsNeeded = true
            finish(message: "マイクが許可されていません。手入力するか、iPhoneの設定を確認してください。", token: token); return
        }
        guard await waitForActive(token: token), token == generation else { return }
        guard client.isAvailable else {
            finish(message: "日本語音声認識を今は利用できません。再試行か手入力で続けられます。", token: token); return
        }
        phase = .recording
        do {
            client.configure(hints: Array(hints.prefix(100)))
            try startSegment(token: token, restarting: false)
            guard token == generation else { return }
            timer = Task { [weak self, recordingLimit] in
                try? await Task.sleep(for: recordingLimit)
                guard !Task.isCancelled, let self, token == self.generation else { return }
                self.stop()
            }
        } catch { finish(message: "マイクを開始できませんでした。再試行か手入力で続けられます。", token: token) }
    }
    private func startSegment(token: UUID, restarting: Bool) throws {
        segment = UUID()
        let current = segment
        let result: @MainActor (String?, Bool, Bool) -> Void = { [weak self] text, final, failed in
            guard let self, token == self.generation, current == self.segment else { return }
            if let text { self.transcript = self.joined(self.completedText, text) }
            if failed {
                self.finish(message: "音声認識を終了しました。読み取れた文章を直すか、手入力してください。", token: token)
            } else if final {
                guard self.phase == .recording else { self.finish(message: nil, token: token); return }
                self.completedText = self.transcript
                do { try self.startSegment(token: token, restarting: true) }
                catch { self.finish(message: "音声認識を終了しました。読み取れた文章を確認してください。", token: token) }
            }
        }
        let interrupted: @MainActor () -> Void = { [weak self] in
            guard let self, token == self.generation, current == self.segment else { return }
            self.cancel(message: "マイクの利用が中断されました。再試行か手入力で続けられます。")
        }
        if restarting { try client.restart(result: result, interrupted: interrupted) }
        else { try client.start(result: result, interrupted: interrupted) }
    }
    private func joined(_ prefix: String, _ partial: String) -> String {
        String([prefix, partial].filter { !$0.isEmpty }.joined(separator: "\n").prefix(4000))
    }
    private func waitForActive(token: UUID) async -> Bool {
        guard token == generation else { return false }
        if activity == .active { return true }
        if activity == .background { cancel(message: stoppedMessage); return false }
        phase = .waitingForActive
        return await withCheckedContinuation { activation = $0 }
    }
    func stop() {
        guard busy else { return }
        guard recording else { cancel(); return }
        let token = generation
        phase = .finishing; client.stop(); timer?.cancel()
        guard token == generation else { return }
        timer = Task { [weak self, finishingLimit] in
            try? await Task.sleep(for: finishingLimit)
            guard !Task.isCancelled, let self, token == self.generation else { return }
            self.finish(message: nil, token: token)
        }
    }
    func cancel(message: String? = nil, erase: Bool = false) {
        generation = UUID(); segment = UUID(); cleanup()
        if erase { transcript = "" }
        completedText = ""
        if let message { self.message = message }
    }
    private func finish(message: String?, token: UUID) {
        guard token == generation else { return }
        generation = UUID(); segment = UUID(); cleanup(); completedText = ""; self.message = message
    }
    private func cleanup() {
        timer?.cancel(); timer = nil; client.cancel(); phase = .idle
        let pending = activation; activation = nil; pending?.resume(returning: false)
    }
}
