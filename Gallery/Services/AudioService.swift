import AVFoundation
import Foundation

@MainActor
final class AudioService {
    static let shared = AudioService()

    private var ambientQueuePlayer: AVQueuePlayer?
    private var ambientLooper: AVPlayerLooper?
    private var currentAmbientName: String?

    private var sfxPlayers: [String: AVAudioPlayer] = [:]

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

    @discardableResult
    func playOneShot(named name: String, volume: Float = 0.85) -> TimeInterval {
        guard let url = resolveAudioURL(named: name) else { return 0 }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            sfxPlayers[name] = player
            return player.duration
        } catch {
            return 0
        }
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
