import AppKit
import AthenaCore
import SwiftUI

/// One screen at a time: a task (LeetCode, then Java) or the progress calendar.
/// The window height follows the content, so there is no empty space below it.
struct DashboardView: View {
    static let width: CGFloat = 640
    /// Outer padding on the left and right of every screen.
    static let gutter: CGFloat = 44

    @Bindable var model: DashboardViewModel
    let onSnooze: () -> Void
    /// False only for offscreen snapshots (ImageRenderer can't draw ScrollView content).
    var scrolls = true
    /// Reports the natural content height so the window can be sized to fit it.
    var onContentHeightChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.gutter)
                .padding(.top, 48)
                .padding(.bottom, 18)
                .background(measureChrome)
            if scrolls {
                FittingScrollView(maxHeight: maxPageHeight, contentHeight: $model.pageContentHeight) { page }
            } else {
                page
            }
            footer
                .padding(.horizontal, Self.gutter)
                .padding(.top, 22)
                .padding(.bottom, 48)
                .background(measureChrome)
        }
        .onPreferenceChange(ChromeHeightKey.self) { model.chromeHeight = $0 }
        .font(Theme.body)
        .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(ContentHeightKey.self) { onContentHeightChange?($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $model.showingLearnings) {
            LearningsView(summary: model.summary) { model.showingLearnings = false }
        }
    }

    /// Whatever the screen allows after the header and footer; anything longer (e.g. Java feedback) scrolls.
    private var maxPageHeight: CGFloat { max(model.maxContentHeight - model.chromeHeight, 200) }

    private var measureChrome: some View {
        GeometryReader { Color.clear.preference(key: ChromeHeightKey.self, value: $0.size.height) }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(Theme.red)
            }
            switch model.page {
            case .intro: IntroView(model: model)
            case .leetcode: LeetCodeCardView(model: model)
            case .java: JavaChallengeCardView(model: model.challenge)
            case .progress: TrackerView(model: model)
            }
        }
        .padding(.horizontal, Self.gutter)
    }

    /// The greeting and date belong to the start screen; everywhere else the app name takes their place.
    private var header: some View {
        HStack(alignment: model.page == .intro ? .top : .center) {
            if model.page == .intro {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATHENA").font(Theme.label).tracking(2.5).foregroundStyle(Theme.green)
                        .padding(.bottom, 4)
                    Text(model.greeting).font(.system(size: 28, weight: .semibold))
                    Text(model.dateText).foregroundStyle(Theme.secondary)
                }
            } else {
                Text("ATHENA").font(.system(size: 22, weight: .semibold)).tracking(3)
            }
            Spacer()
            ProgressBadge(done: model.completedToday, active: model.page == .progress) { model.toggleProgress() }
        }
    }

    /// Navigation centred; snooze small in the bottom-right corner.
    private var footer: some View {
        ZStack {
            HStack(spacing: 10) {
                if model.page == .progress {
                    Button("‹ Back") { model.toggleProgress() }.buttonStyle(SecondaryButtonStyle())
                } else if model.page != .intro {  // the intro's Start button is its only way forward
                    navButton("‹ Prev", to: model.previousPage)
                    navButton("Next ›", to: model.nextPage)
                }
            }
            HStack {
                Spacer()
                Button("Snooze 1h", action: onSnooze)
                    .buttonStyle(.plain)
                    .font(Theme.small)
                    .foregroundStyle(Theme.tertiary)
                    .help("Hide Athena for an hour")
            }
        }
    }

    /// Dimmed (not hidden) at either end so the centred pair keeps its position.
    private func navButton(_ title: String, to target: DashboardViewModel.Page?) -> some View {
        Button(title) { if let target { model.show(target) } }
            .buttonStyle(SecondaryButtonStyle())
            .opacity(target == nil ? 0.3 : 1)
            .disabled(target == nil)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Header + footer heights, summed.
private struct ChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private struct ScrollContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A ScrollView that is exactly as tall as its content, up to `maxHeight`, so it has a natural height.
/// The measured height is stored by the caller (a view-model property) instead of `@State`; see DashboardViewModel.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @Binding var contentHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content.background(GeometryReader {
                Color.clear.preference(key: ScrollContentHeightKey.self, value: $0.size.height)
            })
        }
        // Show the scroll bar whenever there is more to read, so overflowing content is obvious.
        .scrollIndicators(contentHeight > maxHeight ? .visible : .never)
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .onPreferenceChange(ScrollContentHeightKey.self) { contentHeight = $0 }
    }
}

/// First screen of the day: an inviting line, a teaser of what's waiting, and a single way in.
private struct IntroView: View {
    let model: DashboardViewModel

    /// Rotates by day of year so the greeting doesn't go stale, but stays the same all day.
    private static let openers = [
        "Today's practice is ready. Let's keep you sharp.",
        "Twenty minutes today keeps your skills fresh.",
        "Your daily practice is lined up. Ready?",
        "A new problem and today's Java Daily are waiting.",
        "Stay in touch with your craft. Today's practice is ready.",
        "Let's see what today brings.",
        "Small reps, every day. Today's are ready.",
    ]

    private var leetcodeDone: Bool { model.session?.leetcodeCompleted ?? false }
    private var javaDone: Bool { model.session?.javaCompleted ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(headline)
                    .font(.system(size: 21, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(teasers, id: \.self) { line in
                    Text(line).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Start  →") { model.showFirstIncompleteTask() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        switch (leetcodeDone, javaDone) {
        case (false, false):
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            return Self.openers[day % Self.openers.count]
        case (true, false): return "One down. Java Daily is still waiting."
        case (false, true): return "Halfway there. Today's LeetCode problem is waiting."
        case (true, true): return "All done for today. Nice work."
        }
    }

    /// Hints built from today's actual content — enough to spark curiosity, never the answer.
    private var teasers: [String] {
        var lines: [String] = []
        if !leetcodeDone, let title = model.session?.leetcodeTitle {
            let difficulty = model.session?.leetcodeDifficulty.map { "a \($0) problem: " } ?? ""
            lines.append("LeetCode has \(difficulty)“\(title)”.")
        }
        if !javaDone, let topic = model.challenge.challenge?.topic {
            lines.append("Java Daily covers \(topic) today.")
        }
        if model.streak > 0, !(leetcodeDone && javaDone) {
            lines.append("Finish both to make it day \(model.streak + 1) of your streak.")
        }
        return lines
    }
}

/// Top-right calendar button: today's progress, opens the progress screen.
private struct ProgressBadge: View {
    let done: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "calendar").font(.system(size: 16))
                Text("\(done)/2").font(Theme.mono)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(done == 2 ? Theme.green : Theme.text)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Theme.green : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Progress calendar")
    }
}

struct LeetCodeCardView: View {
    let model: DashboardViewModel

    var body: some View {
        let session = model.session
        let solved = session?.leetcodeCompleted ?? false
        Card(label: "01  LEETCODE DAILY", trailing: solved ? "SOLVED" : "TO DO",
             trailingColor: solved ? Theme.green : Theme.secondary) {
            switch model.leetcodeState {
            case .loading where session?.leetcodeTitle == nil:
                Text("Fetching today's problem…").foregroundStyle(Theme.secondary)
            case .failed(let message) where session?.leetcodeTitle == nil:
                VStack(alignment: .leading, spacing: 12) {
                    Text(message).foregroundStyle(Theme.secondary)
                    HStack(spacing: 10) {
                        Button("Open daily challenge →") { model.openLeetCode() }.buttonStyle(PrimaryButtonStyle())
                        Button("Retry") { Task { await model.loadLeetCode() } }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                if let id = session?.leetcodeProblemId {
                                    Text("#\(id)").font(Theme.mono).foregroundStyle(Theme.secondary)
                                }
                                Text(session?.leetcodeTitle ?? "").font(Theme.title)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(session?.leetcodeDifficulty ?? "")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.difficultyColor(session?.leetcodeDifficulty))
                            Button("Open on LeetCode  →") { model.openLeetCode() }
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                        SolvedCheckbox(solved: solved) { model.setLeetCodeSolved(!solved) }
                    }
                    Text("Completion is self-reported; Athena doesn't check your LeetCode account.")
                        .font(Theme.small).foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

/// Large custom checkbox for marking the problem solved.
private struct SolvedCheckbox: View {
    let solved: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(solved ? Theme.green : Color.clear)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(solved ? Theme.green : Theme.secondary, lineWidth: 1.5)
                    if solved {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.black)
                    }
                }
                .frame(width: 28, height: 28)
                Text(solved ? "Solved" : "Mark solved")
                    .font(Theme.small)
                    .foregroundStyle(solved ? Theme.green : Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(solved ? "Mark as not solved" : "Mark today's problem as solved")
    }
}
