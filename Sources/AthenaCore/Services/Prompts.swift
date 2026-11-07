import Foundation

/// Prompt text and JSON schemas sent to Ollama (`format` = JSON schema → constrained decoding).
enum Prompts {
    static let learnerProfile = """
        The learner is a backend software engineer with 4+ years of experience who uses Java as their interview \
        language. They can solve easy DSA problems but are inconsistent on mediums, and they don't write Java every day, \
        so their fluency fades: they hesitate over collections APIs, method names and signatures, comparators, \
        streams, and everyday language rules.
        """

    /// The single most important instruction: what these exercises are *for*.
    static let purpose = """
        Purpose of the exercise: a short daily practice ("Java Daily") that keeps the learner in touch with Java and \
        steadily makes them more proficient — the way a musician practises scales. Success means that over weeks they \
        write idiomatic Java quickly and confidently, recall the right API without searching, and avoid common \
        mistakes, especially while solving interview-style problems.
        It is NOT a brain-teaser, trick question, puzzle or trivia quiz. Do not try to catch the learner out with \
        obscure corner cases, contrived code nobody would write, or language-lawyer details. Test what a fluent Java \
        developer uses in real code and in coding interviews.
        """

    static let generatorSystem = """
        You write short daily Java practice exercises (about five minutes each).
        \(learnerProfile)
        \(purpose)
        What a good exercise looks like:
        - Code that looks like real Java: the collections, string handling, sorting/comparators, streams, \
        exceptions, equals/hashCode and generics patterns used in backend work and in DSA solutions.
        - It exercises one practical skill: choosing or recalling the right API, knowing how a common method behaves \
        (e.g. remove(int) vs remove(Object), putIfAbsent vs put, poll vs remove), writing a correct comparator, \
        or applying an idiom (getOrDefault/merge for counting, ArrayDeque as a stack, PriorityQueue for top-k).
        - Its explanation teaches something reusable: why the answer is right and when to use this in practice, \
        so the learner leaves slightly more fluent.
        - Easy = core API or idiom; Medium = two everyday things combined, or a common mistake to recognise; \
        Hard = a realistic small task that needs fluent use of several APIs.
        - A bare lookup or printing a literal is too trivial; a contrived trick is too obscure. Aim between them.
        Rules:
        - Target Java 17. Code must compile and be deterministic: no randomness, no time, no I/O except System.out, \
        no threads, and never rely on HashMap/HashSet iteration order.
        - Never include the answer in the question or code.
        - Keep code under 15 lines. Use only java.util and java.util.stream.
        - Respond with JSON only.
        """

    static let evaluatorSystem = """
        You grade answers to short daily Java practice exercises.
        \(purpose)
        Judge only what is written. Accept any correct, idiomatic Java solution, not just the reference; don't penalise \
        style or naming. When an answer is wrong, the goal is to help the learner improve their practical Java, so \
        name the specific API or rule they misremembered. Respond with JSON only.
        """

    static func typeInstructions(_ type: ExerciseType) -> String {
        switch type {
        case .predictOutput:
            "Provide a code snippet that is the body of main (assume `import java.util.*;`). The question asks what it prints. expectedAnswer is the exact stdout, nothing else."
        case .identifyBug:
            "Provide a short snippet containing exactly one realistic bug. The question asks the learner to identify it and say how to fix it. expectedAnswer describes the bug and the fix."
        case .fixCode:
            "Provide a short snippet with a bug. The question asks the learner to rewrite it correctly. expectedAnswer is the corrected code."
        case .explainConcept:
            "Ask the learner to explain one concept in a few sentences. code may be empty. expectedAnswer is a model answer of 2-4 sentences."
        case .apiRecall:
            "Describe a concrete everyday job and ask which standard library method (or short expression) does it. expectedAnswer is just the method name like getOrDefault, or the shortest expression. List common alternative spellings in acceptableAnswers. code must be an empty string unless the question refers to a snippet; never repeat the question in code."
        case .completeCode:
            "Provide code with a single ________ blank. expectedAnswer is the code that fills the blank."
        case .smallCoding:
            "Ask for one small method (under 15 lines) with a clear signature. code may be empty. expectedAnswer is a reference implementation."
        }
    }

    static let challengeSchema = """
        {"type":"object","properties":{
          "question":{"type":"string"},
          "code":{"type":"string"},
          "expectedAnswer":{"type":"string"},
          "acceptableAnswers":{"type":"array","items":{"type":"string"}},
          "explanation":{"type":"string"},
          "evaluationCriteria":{"type":"array","items":{"type":"string"}}
        },"required":["question","code","expectedAnswer","acceptableAnswers","explanation","evaluationCriteria"]}
        """

    static let outputCheckSchema = """
        {"type":"object","properties":{"output":{"type":"string"}},"required":["output"]}
        """

    static let diagnosisSchema = """
        {"type":"object","properties":{
          "misunderstanding":{"type":"string"},
          "mistakeCategory":{"type":"string","enum":["conceptual","api_misuse","syntax","edge_case","careless"]}
        },"required":["misunderstanding","mistakeCategory"]}
        """

    static let criteriaSchema = """
        {"type":"object","properties":{
          "criteria":{"type":"array","items":{"type":"object","properties":{
            "index":{"type":"integer"},"met":{"type":"boolean"},"note":{"type":"string"}},"required":["index","met"]}},
          "isCorrect":{"type":"boolean"},
          "mistakeCategory":{"type":"string","enum":["none","conceptual","api_misuse","syntax","edge_case","careless","incomplete"]},
          "feedback":{"type":"string"},
          "misunderstanding":{"type":"string"}
        },"required":["criteria","isCorrect","mistakeCategory","feedback","misunderstanding"]}
        """
}
