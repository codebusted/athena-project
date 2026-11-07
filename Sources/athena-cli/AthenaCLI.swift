import AthenaCore
import Foundation

// `athena` — terminal companion for tuning and inspecting Athena. Reads and writes the same SQLite
// database as the app; the app picks up changes the next time it schedules an exercise.

let usage = """
    athena — tune your Athena coach from the terminal

    Inspect
      status                     Today's tasks, streak and totals
      topics                     Per-topic progress computed from your attempts
      summary                    Java learnings summary (strong / needs work)
      next                       Which topic, difficulty and type the scheduler would pick now
      prefs                      All stored preferences

    Tune
      tune "<request>"           Describe what you want in plain English; the local model maps it to settings
      prompt "<text>"            Extra guidance added to every exercise prompt (prompt --clear to remove)
      focus <topic>[,<topic>]    Practise these topics more (focus --clear)
      exclude <topic>[,<topic>]  Never schedule these topics (exclude --clear)
      difficulty auto|easy|medium|hard
      types <type>[,<type>]|all  Allowed exercise types: \(ExerciseType.allCases.map(\.rawValue).joined(separator: ", "))
      add-topic "<name>" [category]
      model <ollama-tag>         Model to use (default qwen3:4b)
      think on|off               Enable reasoning for generation/grading (slower)

    Maintenance
      unsnooze                   Clear an active snooze
      generate [--think]         Dry-run: write the next exercise and print it with timing (nothing saved)
      grade <bank-id> "<answer>" Try the grader on a curated question (nothing saved)
      verify-bank                Compile and run the curated predict-output questions with your JDK
      db                         Print the database path
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func splitList(_ args: ArraySlice<String>) -> [String] {
    args.joined(separator: " ").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

func resolveTopics(_ names: [String], store: AthenaStore) throws -> [String] {
    try names.map { name in
        guard let topic = try store.progressRepo.topic(named: name) else {
            let known = try store.progressRepo.topics().map(\.name).joined(separator: ", ")
            fail("Unknown topic \"\(name)\". Known topics: \(known)\nAdd one with: athena add-topic \"\(name)\"")
        }
        return topic.name
    }
}

@main
enum AthenaCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, !["-h", "--help", "help"].contains(command) else {
            print(usage)
            exit(0)
        }
        let rest = args.dropFirst()

        let store: AthenaStore
        do { store = try AthenaStore.openDefault() } catch { fail("Couldn't open \(Database.defaultURL.path): \(error)") }
        let prefs = store.preferences

        do {
            switch command {
            case "status", "today":
                let s = try store.sessions.ensureSession(for: store.today)
                let totals = try store.sessions.totals()
                print("Today (\(store.today)): \(s.completedCount)/2 done")
                print("  LeetCode  \(s.leetcodeCompleted ? "✓" : "·")  \(s.leetcodeTitle.map { "#\(s.leetcodeProblemId ?? "") \($0) (\(s.leetcodeDifficulty ?? ""))" } ?? "not fetched yet")")
                print("  Java      \(s.javaCompleted ? "✓" : "·")  \((try store.storedChallenge(for: store.today)).map { "\($0.topic) · \($0.type.label)" } ?? "not generated yet")")
                print("Streak \(try store.sessions.currentStreak(today: store.today, clock: store.clock)) · best \(try store.sessions.longestStreak(clock: store.clock)) · LeetCode \(totals.leetcode) · Java \(totals.java)")

            case "topics":
                let progress = try store.allProgress()
                print(pad("TOPIC", 22) + pad("STATUS", 16) + pad("ATTEMPTS", 10) + pad("RECENT", 8) + "NEXT REVISION")
                for p in progress.sorted(by: { ($0.attempts == 0 ? 2 : $0.mastery) < ($1.attempts == 0 ? 2 : $1.mastery) }) {
                    let next = p.nextRevisionAt.map { store.clock.dayString(for: $0) } ?? "–"
                    print(pad(p.topic.name, 22) + pad(p.status.rawValue, 16) + pad("\(p.correctAttempts)/\(p.attempts)", 10)
                        + pad(p.attempts == 0 ? "–" : pct(p.recentAccuracy), 8) + next)
                }

            case "summary":
                let s = try store.summary()
                guard s.totalAttempts > 0 else { print("No graded Java exercises yet."); break }
                print("\(s.totalAttempts) graded exercises · \(s.overallAccuracy.map(pct) ?? "–") correct overall\n")
                if !s.strong.isEmpty { print("Strong:          " + s.strong.joined(separator: ", ")) }
                if !s.needsWork.isEmpty { print("Needs more work:  " + s.needsWork.joined(separator: ", ")) }
                if !s.recent.isEmpty { print("Recent:          " + s.recent.joined(separator: ", ")) }
                print("")
                for line in s.lines { print("• \(line.topic) — \(line.status.rawValue)\n    \(line.detail)") }

            case "next":
                let request = try store.nextRequest()
                print("Next exercise: \(request.topic) · \(request.difficulty.rawValue) · \(request.type.label)\n")
                let ranked = store.engine.rankedCandidates(try store.allProgress(), settings: try store.engineSettings(), now: Date())
                print("Top candidates:")
                for c in ranked.prefix(5) {
                    print("  " + pad(c.progress.topic.name, 22) + String(format: "priority %.2f", c.priority))
                }

            case "prefs":
                let all = try prefs.all()
                if all.isEmpty { print("No preferences set (defaults: model qwen3:4b, think off, difficulty auto).") }
                for (k, v) in all { print(pad(k, 22) + v) }

            case "prompt":
                if rest.first == "--clear" {
                    try prefs.set(.promptGuidance, nil); print("Prompt guidance cleared.")
                } else if rest.isEmpty {
                    print(try prefs.get(.promptGuidance) ?? "(no prompt guidance set)")
                } else {
                    let text = rest.joined(separator: " ")
                    try prefs.set(.promptGuidance, text); print("Exercises will now follow: \(text)")
                }

            case "focus", "exclude":
                let key: PreferencesRepository.Key = command == "focus" ? .focusTopics : .excludedTopics
                if rest.first == "--clear" {
                    try prefs.setList(key, []); print("\(command) list cleared.")
                } else if rest.isEmpty {
                    print(try prefs.list(key).joined(separator: ", ").nilIfEmpty ?? "(none)")
                } else {
                    let topics = try resolveTopics(splitList(rest), store: store)
                    try prefs.setList(key, topics); print("\(command == "focus" ? "Focusing on" : "Excluding"): \(topics.joined(separator: ", "))")
                }

            case "difficulty":
                guard let value = rest.first?.lowercased() else { print(try prefs.get(.difficulty) ?? "auto"); break }
                if value == "auto" { try prefs.set(.difficulty, nil) }
                else if let d = Difficulty(loose: value) { try prefs.set(.difficulty, d.rawValue) }
                else { fail("Use auto, easy, medium or hard.") }
                print("Difficulty: \(value)")

            case "types":
                guard !rest.isEmpty else { print(try prefs.list(.exerciseTypes).joined(separator: ", ").nilIfEmpty ?? "all"); break }
                if rest.first == "all" { try prefs.setList(.exerciseTypes, []); print("All exercise types enabled."); break }
                let types = splitList(rest)
                let invalid = types.filter { ExerciseType(rawValue: $0) == nil }
                guard invalid.isEmpty else { fail("Unknown type(s): \(invalid.joined(separator: ", "))") }
                try prefs.setList(.exerciseTypes, types); print("Exercise types: \(types.joined(separator: ", "))")

            case "add-topic":
                guard let name = rest.first else { fail("Usage: athena add-topic \"<name>\" [category]") }
                let category = rest.dropFirst().joined(separator: " ").nilIfEmpty ?? "Other"
                let topic = try store.progressRepo.addTopic(name: name, category: category)
                print("Topic available: \(topic.name) (\(topic.category))")

            case "model":
                guard let tag = rest.first else { print(prefs.model); break }
                try prefs.set(.model, tag)
                let status = await OllamaService(baseURL: prefs.ollamaURL, model: tag).status()
                print("Model: \(tag)" + (status.isReady ? "" : "  (not available yet — run `ollama pull \(tag)`)"))

            case "think":
                guard let v = rest.first, ["on", "off"].contains(v) else { print(prefs.thinkEnabled ? "on" : "off"); break }
                try prefs.set(.think, v == "off" ? nil : "on"); print("Reasoning: \(v)")

            case "unsnooze":
                try prefs.set(.snoozeUntil, nil); print("Snooze cleared.")

            case "db":
                print(Database.defaultURL.path)

            case "tune":
                guard !rest.isEmpty else { fail("Usage: athena tune \"more PriorityQueue, harder questions, use streams\"") }
                try await tune(rest.joined(separator: " "), store: store)

            case "verify-bank":
                exit(verifyBank() ? 0 : 1)

            case "grade":
                // Dev aid: grade an answer to a curated question without recording it.
                guard let id = rest.first, let c = QuestionBank.all.first(where: { $0.id == id }) else {
                    fail("Usage: athena grade <bank-id> \"<answer>\"\nIDs: \(QuestionBank.all.map(\.id).joined(separator: ", "))")
                }
                let e = await store.evaluate(c, answer: rest.dropFirst().joined(separator: " "))
                print("\(c.question)\n\nVerdict: \(e.isCorrect.map { $0 ? "correct" : "incorrect" } ?? "unverified") via \(e.method.rawValue)"
                    + (e.score.map { String(format: " (score %.2f)", $0) } ?? ""))
                print("Mistake: \(e.mistakeCategory.label)\nFeedback: \(e.feedback)")
                if let m = e.misunderstanding { print("Misunderstanding: \(m)") }

            case "generate":
                // Dry run: writes an exercise for the scheduler's next pick without saving it. Useful for
                // checking prompt guidance or comparing `think on` vs `off` latency/quality.
                var ollama = store.ollama()
                if rest.contains("--think") { ollama.think = true }
                let request = try store.nextRequest()
                print("Generating \(request.topic) · \(request.difficulty.rawValue) · \(request.type.rawValue) with \(ollama.model) (think \(ollama.think ? "on" : "off"))…")
                let started = Date()
                let outcome = await ExerciseGenerator(ollama: ollama).generate(
                    request, guidance: try prefs.get(.promptGuidance), recentQuestions: [], usedBankIds: [])
                let seconds = String(format: "%.1fs", Date().timeIntervalSince(started))
                if case .fallback(_, let reason) = outcome { print("Fell back to the bank after \(seconds): \(reason)") }
                else { print("Generated in \(seconds)") }
                let c = outcome.challenge
                print("\nQ: \(c.question)\n\(c.code ?? "")\n\nExpected: \(c.expectedAnswer)\nWhy: \(c.explanation)")
                if !c.evaluationCriteria.isEmpty { print("Criteria:\n  - " + c.evaluationCriteria.joined(separator: "\n  - ")) }

            default:
                fail("Unknown command \(command). Run `athena help`.")
            }
        } catch {
            fail("Error: \(error.localizedDescription)")
        }
    }
}

/// Maps a natural-language request to structured settings. The model only proposes; every value is validated
/// against known topics/enums before anything is saved.
func tune(_ request: String, store: AthenaStore) async throws {
    let prefs = store.preferences
    struct Proposal: Decodable {
        let focusTopics: [String]
        let excludeTopics: [String]
        let difficulty: String
        let exerciseTypes: [String]
        let promptGuidance: String
    }
    let topics = try store.progressRepo.topics().map(\.name)
    let schema = """
        {"type":"object","properties":{
          "focusTopics":{"type":"array","items":{"type":"string","enum":\(String(decoding: try JSONEncoder().encode(topics), as: UTF8.self))}},
          "excludeTopics":{"type":"array","items":{"type":"string"}},
          "difficulty":{"type":"string","enum":["unchanged","auto","easy","medium","hard"]},
          "exerciseTypes":{"type":"array","items":{"type":"string","enum":\(String(decoding: try JSONEncoder().encode(ExerciseType.allCases.map(\.rawValue)), as: UTF8.self))}},
          "promptGuidance":{"type":"string"}
        },"required":["focusTopics","excludeTopics","difficulty","exerciseTypes","promptGuidance"]}
        """
    let prompt = """
        Convert the learner's request into settings for a Java practice app.
        Known topics: \(topics.joined(separator: ", "))
        Exercise types: \(ExerciseType.allCases.map { "\($0.rawValue) (\($0.label))" }.joined(separator: ", "))
        Only fill focusTopics/excludeTopics/exerciseTypes when the request clearly asks for them; otherwise use [].
        difficulty is "unchanged" unless the request mentions difficulty.
        promptGuidance: a short instruction for the exercise writer capturing any style or content wishes not covered above, or "".

        Request: \(request)
        """
    let ollama = store.ollama()
    let proposal: Proposal
    do {
        proposal = try await ollama.chatJSON(
            system: "You translate requests into JSON settings. Respond with JSON only.", user: prompt, schema: schema,
            temperature: 0, as: Proposal.self)
    } catch {
        try prefs.set(.promptGuidance, request)
        print("Local model unavailable (\(error.localizedDescription)).\nSaved your text as prompt guidance instead.")
        return
    }

    let valid = Set(topics.map { $0.lowercased() })
    let focus = proposal.focusTopics.filter { valid.contains($0.lowercased()) }
    let exclude = proposal.excludeTopics.filter { valid.contains($0.lowercased()) && !focus.contains($0) }
    let types = proposal.exerciseTypes.filter { ExerciseType(rawValue: $0) != nil }
    var changes: [String] = []
    if !focus.isEmpty { try prefs.setList(.focusTopics, focus); changes.append("focus → \(focus.joined(separator: ", "))") }
    if !exclude.isEmpty { try prefs.setList(.excludedTopics, exclude); changes.append("exclude → \(exclude.joined(separator: ", "))") }
    if !types.isEmpty { try prefs.setList(.exerciseTypes, types); changes.append("types → \(types.joined(separator: ", "))") }
    switch proposal.difficulty {
    case "auto": try prefs.set(.difficulty, nil); changes.append("difficulty → auto")
    case "easy", "medium", "hard":
        try prefs.set(.difficulty, Difficulty(loose: proposal.difficulty)!.rawValue); changes.append("difficulty → \(proposal.difficulty)")
    default: break
    }
    let guidance = proposal.promptGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
    if !guidance.isEmpty { try prefs.set(.promptGuidance, guidance); changes.append("prompt → \(guidance)") }
    print(changes.isEmpty ? "Nothing to change." : "Updated:\n  " + changes.joined(separator: "\n  "))
}

/// Runs every curated predict-output snippet through javac/java and compares stdout with the stored answer.
/// Only curated, in-repo code is executed here — never LLM output.
func verifyBank() -> Bool {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("athena-verify-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    func run(_ tool: String, _ arguments: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool] + arguments
        p.currentDirectoryURL = dir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    var allPassed = true
    for (i, c) in QuestionBank.all.filter({ $0.type == .predictOutput }).enumerated() {
        let name = "Q\(i)"
        let source = "import java.util.*;\nimport java.util.stream.*;\npublic class \(name) {\n public static void main(String[] args) {\n\(c.code ?? "")\n }\n}\n"
        try? source.write(to: dir.appendingPathComponent("\(name).java"), atomically: true, encoding: .utf8)
        let (compiled, compileOutput) = run("javac", ["\(name).java"])
        guard compiled == 0 else {
            print("✗ \(c.id): compile error\n\(compileOutput)"); allPassed = false; continue
        }
        let (_, output) = run("java", ["-cp", ".", name])
        let ok = ChallengeEvaluator.matchesReference(output, c)
        print("\(ok ? "✓" : "✗") \(c.id)" + (ok ? "" : ": expected \(c.expectedAnswer.debugDescription), got \(output.debugDescription)"))
        allPassed = allPassed && ok
    }
    return allPassed
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
