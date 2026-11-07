import AthenaCore
import Foundation
import Observation

@MainActor
@Observable
final class ChallengeViewModel {
    enum Phase: Equatable {
        case idle
        case generating
        case answering
        case evaluating
        /// The LLM verdict couldn't be validated; the user compares with the reference and grades themselves.
        case selfGrade(Evaluation)
        case feedback(Evaluation)
        case failed(String)
    }

    let store: AthenaStore
    private(set) var phase: Phase = .idle
    private(set) var challenge: JavaChallenge?
    private(set) var fallbackNote: String?
    private(set) var ollamaStatus: OllamaStatus = .checking
    private(set) var revisionNote: String?
    /// Shown when an attempt was graded but couldn't be written to the database.
    private(set) var saveError: String?
    /// True once today's mandatory exercise is done and the user asked for another one.
    private(set) var isExtraPractice = false
    var answer = ""

    var onRecorded: (() -> Void)?

    private var day = ""
    private var generationTask: Task<Void, Never>?

    // Prefetch: the next exercise is prepared in the background while the user works on the current one, so
    // "Practice another" is instant. It is held in memory only and saved when it's actually shown.
    private var prefetched: GenerationOutcome?
    private var prefetchTask: Task<Void, Never>?
    /// The on-screen exercise the prefetch was prepared against (it must be a different topic and question).
    private var prefetchedFor: String?

    init(store: AthenaStore) { self.store = store }

    func resetForNewDay() {
        generationTask?.cancel()
        cancelPrefetch()
        prefetched = nil
        phase = .idle
        challenge = nil
        answer = ""
        fallbackNote = nil
        revisionNote = nil
        saveError = nil
        isExtraPractice = false
    }

    func loadIfNeeded(day: String) {
        self.day = day
        Task { ollamaStatus = await store.ollama().status() }
        guard phase == .idle || phase.isFailure else { return }
        do {
            if let stored = try store.storedChallenge(for: day) {
                challenge = stored
                if let previous = try store.challenges.latestAttempt(challengeId: stored.id),
                   previous.attempt.method.countsTowardProgress {
                    answer = previous.attempt.userAnswer
                    phase = .feedback(restore(previous.attempt, feedback: previous.feedback,
                                              misunderstanding: previous.misunderstanding, challenge: stored))
                    revisionNote = try store.revisionText(for: stored.topic)
                } else {
                    phase = .answering
                }
                ensurePrefetch()
            } else {
                generate(useBank: false)
            }
        } catch {
            phase = .failed("Couldn't load today's exercise: \(error.localizedDescription)")
        }
    }

    func retryOllama() {
        Task {
            ollamaStatus = .checking
            ollamaStatus = await store.ollama().status()
            if ollamaStatus.isReady, challenge == nil || challenge?.source == .bank, phase == .answering || phase.isFailure {
                generate(useBank: false)
            }
        }
    }

    func useSavedQuestion() { generate(useBank: true) }

    /// Shows the prefetched exercise if it's ready, waits for it if it's still being written, or writes one now.
    func practiceAnother() {
        isExtraPractice = true
        if let ready = prefetched {
            show(ready)
        } else if let pending = prefetchTask {
            beginLoading()
            generationTask = Task {
                await pending.value
                guard !Task.isCancelled else { return }
                if let ready = prefetched { show(ready) } else { generate(useBank: false) }
            }
        } else {
            generate(useBank: false)
        }
    }

    private func beginLoading() {
        generationTask?.cancel()
        phase = .generating
        answer = ""
        fallbackNote = nil
        revisionNote = nil
        saveError = nil
    }

    /// Saves a prefetched exercise and puts it on screen, then starts preparing the one after it.
    private func show(_ outcome: GenerationOutcome) {
        do {
            try store.adopt(outcome.challenge, assignToDay: isExtraPractice ? nil : day)
        } catch {
            phase = .failed("Couldn't prepare an exercise: \(error.localizedDescription)")
            return
        }
        prefetched = nil
        prefetchedFor = nil
        challenge = outcome.challenge
        answer = ""
        revisionNote = nil
        saveError = nil
        if case .fallback(_, let reason) = outcome { fallbackNote = "Saved question — \(reason)" } else { fallbackNote = nil }
        phase = .answering
        ensurePrefetch()
    }

    // MARK: Prefetch

    private func ensurePrefetch() {
        guard let current = challenge else { return }
        if prefetchedFor == current.id, prefetched != nil || prefetchTask != nil { return }
        // A ready exercise on another topic is still a good "next" even if the one on screen changed.
        if let ready = prefetched, ready.challenge.topic.caseInsensitiveCompare(current.topic) != .orderedSame,
           ready.challenge.id != current.id {
            prefetchedFor = current.id
            return
        }
        cancelPrefetch()
        prefetched = nil
        prefetchedFor = current.id
        prefetchTask = Task { [store] in
            let modelReady = await store.ollama().status().isReady
            guard !Task.isCancelled else { return }
            let outcome = try? await store.prepareChallenge(useBankOnly: !modelReady, avoiding: current)
            guard !Task.isCancelled else { return }
            prefetched = outcome
            prefetchTask = nil
        }
    }

    /// Stops an in-flight prefetch (Ollama aborts generation when the request is dropped).
    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        if prefetched == nil { prefetchedFor = nil }
    }

    private func generate(useBank: Bool) {
        beginLoading()
        let assign: String? = isExtraPractice ? nil : day
        generationTask = Task {
            if !useBank {
                ollamaStatus = await store.ollama().status()
            }
            let bankOnly = useBank || !ollamaStatus.isReady
            do {
                let outcome = try await store.makeChallenge(assignToDay: assign, useBankOnly: bankOnly)
                guard !Task.isCancelled else { return }
                challenge = outcome.challenge
                if case .fallback(_, let reason) = outcome, !useBank { fallbackNote = "Saved question — \(reason)" }
                phase = .answering
                ensurePrefetch()
            } catch is CancellationError {
                return
            } catch {
                phase = .failed("Couldn't prepare an exercise: \(error.localizedDescription)")
            }
        }
    }

    func submit() {
        guard let challenge, phase == .answering,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        phase = .evaluating
        let submitted = answer
        // Ollama handles one request at a time: grading comes first, so pause a prefetch that's still running.
        cancelPrefetch()
        Task {
            let evaluation = await store.evaluate(challenge, answer: submitted)
            if evaluation.method == .unverified {
                phase = .selfGrade(evaluation)
                ensurePrefetch()
            } else {
                persist(evaluation, challenge: challenge, answer: submitted)
            }
        }
    }

    func selfGrade(correct: Bool) {
        guard case .selfGrade(let evaluation) = phase, let challenge else { return }
        persist(ChallengeEvaluator.selfGraded(evaluation, correct: correct), challenge: challenge, answer: answer)
    }

    private func persist(_ evaluation: Evaluation, challenge: JavaChallenge, answer: String) {
        do {
            try store.record(challenge, answer: answer, evaluation: evaluation, day: isExtraPractice ? nil : day)
            revisionNote = try store.revisionText(for: challenge.topic)
            saveError = nil
            phase = .feedback(evaluation)
            onRecorded?()
            ensurePrefetch()
        } catch {
            // Never pretend it was saved: keep the answer on screen so the user can submit again.
            saveError = "Your answer couldn't be saved (\(error.localizedDescription)). Submit again to retry."
            phase = .answering
        }
    }

    private func restore(_ a: ChallengeAttempt, feedback: String, misunderstanding: String?, challenge: JavaChallenge) -> Evaluation {
        Evaluation(
            isCorrect: a.isCorrect, score: a.score, mistakeCategory: a.mistakeCategory, feedback: feedback,
            correctAnswer: challenge.expectedAnswer, explanation: challenge.explanation,
            misunderstanding: misunderstanding, method: a.method)
    }
}

extension ChallengeViewModel.Phase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}
