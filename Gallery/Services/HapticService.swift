import CoreHaptics
import Foundation
import UIKit

@MainActor
final class HapticService {
    static let shared = HapticService()

    private var engine: CHHapticEngine?
    private var supportsHaptics = false
    private var lastTickProgress: [String: Float] = [:]

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        print("📳 [HapticService] Hardware suporta Core Haptics? \(supportsHaptics)")
        setupEngine()
    }

    private func setupEngine() {
        guard supportsHaptics else { return }
        do {
            let newEngine = try CHHapticEngine()
            newEngine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.engine?.start()
                    print("📳 [HapticService] Motor háptico reiniciado com sucesso.")
                }
            }
            newEngine.stoppedHandler = { reason in
                print("⚠️ [HapticService] Motor háptico parou. Razão: \(reason)")
            }
            try newEngine.start()
            engine = newEngine
            print("✅ [HapticService] CHHapticEngine iniciado com sucesso.")
        } catch {
            print("❌ [HapticService] Erro ao iniciar CHHapticEngine: \(error)")
        }
    }

    func playImpact(intensity: Float, sharpness: Float) {
        let clampedIntensity = min(max(intensity, 0), 1)
        let clampedSharpness = min(max(sharpness, 0), 1)

        print("📳 [HapticService] Disparando impacto tátil (Intensidade: \(clampedIntensity), Nitidez: \(clampedSharpness))")

        guard supportsHaptics else {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = clampedIntensity > 0.7 ? .heavy : (clampedIntensity > 0.4 ? .medium : .light)
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred(intensity: CGFloat(clampedIntensity))
            return
        }

        do {
            try engine?.start()
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: clampedSharpness)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("❌ [HapticService] Erro ao executar impacto CoreHaptics: \(error)")
        }
    }

    func updateGestureTexture(
        key: String,
        progress: Float,
        step: Float = 0.06,
        intensityRange: ClosedRange<Float> = 0.25...0.65,
        sharpness: Float = 0.6
    ) {
        let clamped = min(max(progress, 0), 1)
        let last = lastTickProgress[key] ?? clamped

        if abs(clamped - last) >= step {
            lastTickProgress[key] = clamped
            let span = intensityRange.upperBound - intensityRange.lowerBound
            let intensity = intensityRange.lowerBound + span * clamped
            // print("📳 [HapticService] Textura contínua [\(key)] progresso: \(String(format: "%.2f", clamped))")
            playImpact(intensity: intensity, sharpness: sharpness)
        }
    }

    func resetGestureTexture(key: String) {
        lastTickProgress.removeValue(forKey: key)
        print("📳 [HapticService] Textura háptica resetada para: \(key)")
    }
}
