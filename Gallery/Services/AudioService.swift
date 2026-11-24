import AVFoundation
import Foundation

@MainActor
final class AudioService {
    static let shared = AudioService()

    private var ambientQueuePlayer: AVQueuePlayer?
    private var ambientLooper: AVPlayerLooper?
    private var currentAmbientName: String?

    private var sfxPlayers: [String: AVAudioPlayer] = [:]

    private var anglePlayers: [String: AVAudioPlayer] = [:]
    private var angleTasks: [String: Task<Void, Never>] = [:]
    private var lastProgress: [String: Float] = [:]
    private var lastDirection: [String: Int] = [:]

    private init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("❌ [AudioService] Falha ao configurar AVAudioSession: \(error)")
        }
    }

    // MARK: - Som Ambiente

    func startAmbientLoop() {
        let hour = Calendar.current.component(.hour, from: Date())
        let isDay = hour >= 6 && hour < 18
        let targetName = isDay ? "LoopDia" : "loopNoite"

        if currentAmbientName == targetName, let player = ambientQueuePlayer {
            if player.rate == 0 { player.play() }
            return
        }

        stopAmbientLoop()
        guard let url = resolveAudioURL(named: targetName) else { return }

        let asset = AVURLAsset(url: url)
        let templateItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.volume = 0.35
        queuePlayer.actionAtItemEnd = .none

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
        queuePlayer.play()

        ambientQueuePlayer = queuePlayer
        ambientLooper = looper
        currentAmbientName = targetName
    }

    func pauseAmbientLoop() {
        ambientQueuePlayer?.pause()
    }

    func resumeAmbientLoop() {
        // Re-evaluate the system hour on foregrounding so a session that
        // crosses day/night boundaries switches to the matching ambience.
        startAmbientLoop()
    }

    func stopAmbientLoop() {
        ambientQueuePlayer?.pause()
        ambientLooper?.disableLooping()
        ambientLooper = nil
        ambientQueuePlayer?.removeAllItems()
        ambientQueuePlayer = nil
        currentAmbientName = nil
    }

    // MARK: - Efeitos Pontuais (One-Shot)

    func playOneShot(named name: String, volume: Float = 0.85) {
        guard let url = resolveAudioURL(named: name) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            sfxPlayers[name] = player
        } catch {}
    }

    // MARK: - Áudio Proporcional à Angulação / Abertura

    func updateAngleGestureSound(
        named name: String,
        interaction: String? = nil,
        progress: Float,
        delta: Float,
        baseVolume: Float = 0.92
    ) {
        let key = interaction ?? name
        let clamped = min(max(progress, 0), 1)
        lastProgress[key] = clamped

        angleTasks[key]?.cancel()
        angleTasks[key] = nil

        guard let player = getOrCreateAnglePlayer(named: name, key: key), player.duration > 0 else { return }

        let speed = abs(delta)
        let targetTime = TimeInterval(clamped) * player.duration
        let direction = delta == 0 ? 0 : (delta > 0 ? 1 : -1)
        let directionChanged = direction != 0
            && lastDirection[key].map { $0 != direction } == true
        if direction != 0 { lastDirection[key] = direction }

        if !player.isPlaying || directionChanged || abs(player.currentTime - targetTime) > 0.12 {
            player.currentTime = min(max(targetTime, 0), max(player.duration - 0.02, 0))
        }

        if speed > 0.0002 {
            let rate = min(max(speed * 40.0, 0.25), 1.85)
            player.rate = rate
            let motionVolume = min(max(speed * 50.0, 0.2), 1.0)
            player.volume = min(max(baseVolume * motionVolume, 0.08), 1.0)
            if !player.isPlaying {
                player.play()
            }
        } else {
            if player.isPlaying {
                player.pause()
            }
        }

        angleTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                self?.anglePlayers[key]?.pause()
            } catch {}
        }
    }

    func finishAngleGestureSound(
        named name: String,
        interaction: String? = nil,
        completed: Bool,
        animationDuration: TimeInterval = 0.25
    ) {
        let key = interaction ?? name
        angleTasks[key]?.cancel()
        angleTasks[key] = nil

        guard let player = anglePlayers[key], player.duration > 0 else {
            lastProgress[key] = 0
            return
        }

        guard completed else {
            player.pause()
            player.currentTime = 0
            lastProgress[key] = 0
            lastDirection[key] = nil
            return
        }

        let remainingSeconds = max(player.duration - player.currentTime, 0)
        if remainingSeconds > 0.02 {
            let safeAnim = max(animationDuration, 0.15)
            let rate = min(max(Float(remainingSeconds / safeAnim), 0.75), 2.0)
            player.rate = rate
            player.volume = 0.92
            if !player.isPlaying {
                player.play()
            }
            let waitTime = remainingSeconds / Double(rate)
            angleTasks[key] = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(waitTime + 0.03))
                    guard !Task.isCancelled else { return }
                    player.pause()
                    player.currentTime = 0
                    self?.lastProgress[key] = 0
                    self?.lastDirection[key] = nil
                } catch {}
            }
        } else {
            player.pause()
            player.currentTime = 0
            lastProgress[key] = 0
            lastDirection[key] = nil
        }
    }

    func stopAllContinuousSounds() {
        for (name, player) in anglePlayers {
            angleTasks[name]?.cancel()
            player.pause()
            player.currentTime = 0
        }
        angleTasks.removeAll()
        lastProgress.removeAll()
        lastDirection.removeAll()
    }

    private func getOrCreateAnglePlayer(named name: String, key: String) -> AVAudioPlayer? {
        if let existing = anglePlayers[key] {
            return existing
        }
        guard let url = resolveAudioURL(named: name),
              let created = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        created.numberOfLoops = 0
        created.enableRate = true
        created.prepareToPlay()
        anglePlayers[key] = created
        return created
    }

    private func resolveAudioURL(named name: String) -> URL? {
        let extensions = ["wav", "mp4", "m4a", "mp3", "aac", "caf"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
