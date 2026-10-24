import Foundation
import AVFoundation

/// Records and plays voice messages.
///
/// Recording uses AAC in an `.m4a` container, which is understood by every
/// iOS device and by the mesh playback helper. The service asks for the
/// microphone permission the first time it is used and reports the state
/// truthfully when the permission was denied.
@MainActor
final class VoiceService: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackProgress: Double = 0
    @Published private(set) var permissionGranted = false
    @Published private(set) var lastErrorMessage: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var durationTimer: Timer?
    private var recordingURL: URL?
    private var playbackURL: URL?

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let granted: Bool = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        permissionGranted = granted
        return granted
    }

    var permissionStatus: AVAudioSession.RecordPermission {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission
        }
        return AVAudioSession.sharedInstance().recordPermission
    }

    // MARK: - Recording

    /// Starts a new recording and returns the file URL when it is finished.
    func startRecording() async throws -> URL {
        guard await requestPermission() else {
            lastErrorMessage = "Microphone access is required to record a voice message."
            throw ResilixError.permissionDenied("microphone")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw ResilixError.persistenceFailed("The recorder could not be started")
        }
        self.recorder = recorder
        recordingURL = url
        recordingDuration = 0
        isRecording = true
        startDurationTimer()
        return url
    }

    /// Stops the recording and returns the file (nil when nothing was recorded).
    @discardableResult
    func stopRecording() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        stopDurationTimer()
        let duration = recorder.currentTime
        recordingDuration = duration
        guard duration > 0.3 else { return nil }
        return recordingURL
    }

    /// Aborts the recording and deletes the file.
    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        stopDurationTimer()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        recordingDuration = 0
    }

    private func startDurationTimer() {
        stopDurationTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.recordingDuration = recorder.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Playback

    func play(url: URL) {
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            playbackURL = url
            isPlaying = true
            playbackProgress = 0
        } catch {
            lastErrorMessage = "The voice message could not be played."
            isPlaying = false
        }
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
    }

    func resumePlayback() {
        player?.play()
        isPlaying = true
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playbackURL = nil
        isPlaying = false
        playbackProgress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        playbackProgress = 0
    }

    func audioPlayer(_ player: AVAudioPlayer, decodedByteCount decodedBytes: Int, totalByteCount totalBytes: Int) {
        guard totalBytes > 0 else { return }
        playbackProgress = Double(decodedBytes) / Double(totalBytes)
    }
}
