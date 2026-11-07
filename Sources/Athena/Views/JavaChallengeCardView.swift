import AthenaCore
import SwiftUI

struct JavaChallengeCardView: View {
    @Bindable var model: ChallengeViewModel

    var body: some View {
        Card(label: "02  JAVA DAILY", trailing: trailing.text, trailingColor: trailing.color) {
            VStack(alignment: .leading, spacing: 14) {
                ollamaBanner
                content
            }
        }
    }

    private var trailing: (text: String, color: Color) {
        switch model.phase {
        case .feedback: model.isExtraPractice ? ("EXTRA", Theme.green) : ("DONE", Theme.green)
        default: ("TO DO", Theme.secondary)
        }
    }

    @ViewBuilder private var ollamaBanner: some View {
        switch model.ollamaStatus {
        case .notRunning:
            statusLine("Ollama isn't running — start it with `ollama serve`. Using saved questions for now.", retry: true)
        case .modelMissing(let name):
            statusLine("Model \(name) isn't downloaded — run `ollama pull \(name)`. Using saved questions for now.", retry: true)
        case .error(let message):
            statusLine("Ollama: \(message)", retry: true)
        case .checking, .ready:
            EmptyView()
        }
    }

    private func statusLine(_ text: String, retry: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.amber).frame(width: 6, height: 6)
            Text(.init(text)).font(Theme.small).foregroundStyle(Theme.secondary)
            Spacer()
            if retry { Button("Retry") { model.retryOllama() }.buttonStyle(LinkButtonStyle()) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .generating:
            VStack(alignment: .leading, spacing: 10) {
                Text("Writing today's exercise with the local model…").foregroundStyle(Theme.secondary)
                Button("Use a saved question instead") { model.useSavedQuestion() }.buttonStyle(LinkButtonStyle())
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(Theme.red)
                Button("Use a saved question") { model.useSavedQuestion() }.buttonStyle(SecondaryButtonStyle())
            }
        case .answering, .evaluating, .selfGrade, .feedback:
            if let challenge = model.challenge { exercise(challenge) }
        }
    }

    @ViewBuilder private func exercise(_ challenge: JavaChallenge) -> some View {
        Text("\(challenge.topic) · \(challenge.difficulty.rawValue) · \(challenge.type.label)")
            .font(Theme.monoSmall).foregroundStyle(Theme.green)
        // Models often format identifiers as `code`; render that inline markdown instead of showing backticks.
        Text(LocalizedStringKey(challenge.question)).font(.system(size: 17)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        if let code = challenge.code, !code.isEmpty { CodeBlock(code: code) }
        if let note = model.fallbackNote {
            Text(note).font(Theme.small).foregroundStyle(Theme.tertiary).lineLimit(2)
        }

        ChallengeAnswerView(model: model, challenge: challenge)

        switch model.phase {
        case .selfGrade(let evaluation): SelfGradeView(evaluation: evaluation, model: model)
        case .feedback(let evaluation):
            FeedbackView(evaluation: evaluation, revisionNote: model.revisionNote) { model.practiceAnother() }
        default: EmptyView()
        }
    }
}

struct ChallengeAnswerView: View {
    @Bindable var model: ChallengeViewModel
    let challenge: JavaChallenge

    private var editable: Bool { model.phase == .answering }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if challenge.type.expectsMultilineAnswer {
                TextEditor(text: $model.answer)
                    .font(Theme.monoSmall)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    // Room to type while answering; compact once submitted so the feedback has the space.
                    .frame(minHeight: editable ? 110 : 60, maxHeight: editable ? 220 : 80)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    .disabled(!editable)
            } else {
                TextField(challenge.type == .predictOutput ? "Exact output" : "Your answer", text: $model.answer)
                    .textFieldStyle(.plain)
                    .font(Theme.mono)
                    .padding(10)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    .disabled(!editable)
                    .onSubmit { model.submit() }
            }
            if let error = model.saveError {
                Text(error).font(Theme.small).foregroundStyle(Theme.red)
            }
            if model.phase == .answering || model.phase == .evaluating {
                HStack(spacing: 12) {
                    Button(model.phase == .evaluating ? "Checking…" : "Submit") { model.submit() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.phase != .answering || model.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if challenge.type.expectsMultilineAnswer {
                        Text("⌘↩ to submit").font(Theme.small).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }
}

struct FeedbackView: View {
    /// The details (answer, explanation, what went wrong) scroll inside this height instead of growing the window.
    static let detailsMaxHeight: CGFloat = 160

    let evaluation: Evaluation
    let revisionNote: String?
    let onPracticeAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(evaluation.isCorrect == true ? "✓ Correct" : "✗ Incorrect")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(evaluation.isCorrect == true ? Theme.green : Theme.red)
                if let score = evaluation.score, evaluation.method == .criteria {
                    Text("\(Int((score * 100).rounded()))% of criteria met").font(Theme.small).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(methodLabel).font(Theme.small).foregroundStyle(Theme.tertiary)
            }
            FittingScrollView(maxHeight: Self.detailsMaxHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    if !evaluation.feedback.isEmpty, evaluation.feedback != "Correct." {
                        Text(evaluation.feedback).font(Theme.body).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    section("Correct answer") { CodeBlock(code: evaluation.correctAnswer) }
                    section("Why") { Text(evaluation.explanation).font(Theme.body).fixedSize(horizontal: false, vertical: true) }
                    if let misunderstanding = evaluation.misunderstanding, evaluation.isCorrect != true {
                        section("What went wrong") {
                            Text(misunderstanding).font(Theme.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.trailing, 14)  // keeps text clear of the scroll bar
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            // Outcome summary on the left, next step on the right: one row instead of three.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if evaluation.isCorrect != true {
                        Text("Mistake: \(evaluation.mistakeCategory.label)").font(Theme.monoSmall).foregroundStyle(Theme.amber)
                    }
                    if let revisionNote {
                        Text(revisionNote).font(Theme.monoSmall).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button("Practice another", action: onPracticeAnother).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    private var methodLabel: String {
        switch evaluation.method {
        case .deterministic: "checked against reference"
        case .criteria: "graded by local model against criteria"
        case .selfGraded: "self-graded"
        case .unverified: "unverified"
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.label).foregroundStyle(Theme.secondary).tracking(1)
            content()
        }
    }
}

struct SelfGradeView: View {
    let evaluation: Evaluation
    let model: ChallengeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(evaluation.feedback).font(Theme.body).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            FittingScrollView(maxHeight: FeedbackView.detailsMaxHeight) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("REFERENCE ANSWER").font(Theme.label).foregroundStyle(Theme.secondary).tracking(1)
                    CodeBlock(code: evaluation.correctAnswer)
                    Text(evaluation.explanation).font(Theme.body).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("I got it right") { model.selfGrade(correct: true) }.buttonStyle(PrimaryButtonStyle())
                Button("I got it wrong") { model.selfGrade(correct: false) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
