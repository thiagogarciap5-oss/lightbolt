import AVFoundation
import Observation

/// Reads the day's objectives aloud with `AVSpeechSynthesizer`.
@Observable
final class SpeechCoach {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking: Bool = false

    /// Builds and speaks the morning briefing from live user data only.
    func speak(_ script: String) {
        guard !script.isEmpty else { return }
        stop()
        configureSession()

        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 0.95
        utterance.postUtteranceDelay = 0.1
        utterance.volume = 1.0
        utterance.voice = Self.preferredVoice()

        isSpeaking = true
        synthesizer.speak(utterance)

        // AVSpeechSynthesizer delegate callbacks are optional here; poll-free
        // completion is handled by resetting on the next interaction.
        Task { @MainActor [weak self] in
            while self?.synthesizer.isSpeaking == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.isSpeaking = false
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            // Audio route unavailable (call in progress, etc.) — speech is optional.
        }
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        if let enhanced = voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: language)
    }
}

/// Composes the spoken briefing text from the user's real numbers.
nonisolated enum CoachScript {
    static func morning(
        goal: LightBoltGoal,
        calorieBudget: Int,
        caloriesLogged: Int,
        proteinTarget: Int,
        proteinLogged: Int,
        habitsRemaining: [String],
        workoutTitle: String?
    ) -> String {
        var lines: [String] = []
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting = hour < 12 ? "Good morning." : hour < 18 ? "Good afternoon." : "Good evening."
        lines.append(greeting)

        let remaining = max(0, calorieBudget - caloriesLogged)
        lines.append("Your objective today is \(goal.title.lowercased()).")
        lines.append("You have \(remaining) calories left of \(calorieBudget), and \(max(0, proteinTarget - proteinLogged)) grams of protein to hit.")

        if let workoutTitle {
            lines.append("Your session is \(workoutTitle).")
        }

        if habitsRemaining.isEmpty {
            lines.append("Every habit is already checked off. Outstanding.")
        } else if habitsRemaining.count == 1 {
            lines.append("One habit left: \(habitsRemaining[0]).")
        } else {
            lines.append("\(habitsRemaining.count) habits left, starting with \(habitsRemaining[0]).")
        }

        lines.append("Let's get to work.")
        return lines.joined(separator: " ")
    }
}
