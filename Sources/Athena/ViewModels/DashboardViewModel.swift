import AppKit
import AthenaCore
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    enum LeetCodeState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// The dashboard shows one thing at a time. The intro leads in via Start; Prev/Next step through `flow`;
    /// progress is reached via the badge.
    enum Page: Equatable {
        case intro
        case leetcode
        case java
        case progress
    }

    static let flow: [Page] = [.leetcode, .java]

    let store: AthenaStore
    let challenge: ChallengeViewModel
    var page: Page = .intro
    /// The page to return to when leaving the progress screen.
    private var lastFlowPage: Page = .intro

    private(set) var day: String
    private(set) var session: DailySession?
    private(set) var leetcodeState: LeetCodeState = .loading
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var totals = (leetcode: 0, java: 0)
    private(set) var monthTitle = ""
    private(set) var monthLeadingBlanks = 0
    private(set) var monthDays: [AthenaStore.MonthDay] = []
    private(set) var summary: LearningSummary?
    var monthAnchor = Date()
    /// Tallest the window's content may be on its current screen (set by the app delegate).
    var maxContentHeight: CGFloat = 800
    // Measured layout heights. Kept here rather than in SwiftUI `@State`, which is a compiler macro in newer
    // SDKs and needs Xcode's macro plugins; the Command Line Tools alone can't build it.
    var chromeHeight: CGFloat = 0
    var pageContentHeight: CGFloat = 0
    var errorMessage: String?
    var showingLearnings = false

    /// Called whenever completion state changes so the menu bar and lifecycle logic stay in sync.
    var onCompletionChange: (() -> Void)?

    init(store: AthenaStore) {
        self.store = store
        day = store.today
        challenge = ChallengeViewModel(store: store)
        challenge.onRecorded = { [weak self] in self?.reloadLocal() }
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    var dateText: String { Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year()) }

    var completedToday: Int { session?.completedCount ?? 0 }

    var isAllDone: Bool { session?.isComplete ?? false }

    /// Where a fresh opening starts: the intro while anything is left, progress when both are done.
    func showStart() {
        show(isAllDone ? .progress : .intro)
    }

    /// LeetCode first; Java once LeetCode is solved; progress when both are done.
    func showFirstIncompleteTask() {
        let leetcodeDone = session?.leetcodeCompleted ?? false
        let javaDone = session?.javaCompleted ?? false
        show(!leetcodeDone ? .leetcode : (!javaDone ? .java : .progress))
    }

    func show(_ page: Page) {
        if page != .progress { lastFlowPage = page }
        self.page = page
    }

    func toggleProgress() {
        page = page == .progress ? lastFlowPage : .progress
    }

    var previousPage: Page? { Self.flow.firstIndex(of: page).flatMap { $0 > 0 ? Self.flow[$0 - 1] : nil } }
    var nextPage: Page? { Self.flow.firstIndex(of: page).flatMap { $0 + 1 < Self.flow.count ? Self.flow[$0 + 1] : nil } }

    /// Full refresh; also handles the app staying open across midnight.
    func refresh() {
        if day != store.today {
            day = store.today
            challenge.resetForNewDay()
            monthAnchor = Date()
        }
        reloadLocal()
        Task { await loadLeetCode() }
        challenge.loadIfNeeded(day: day)
    }

    func reloadLocal() {
        do {
            session = try store.sessions.ensureSession(for: day)
            streak = try store.sessions.currentStreak(today: day, clock: store.clock)
            bestStreak = try store.sessions.longestStreak(clock: store.clock)
            totals = try store.sessions.totals()
            let month = try store.month(containing: monthAnchor)
            monthTitle = month.title
            monthLeadingBlanks = month.leadingBlanks
            monthDays = month.days
            summary = try store.summary()
        } catch {
            errorMessage = error.localizedDescription
        }
        onCompletionChange?()
    }

    func loadLeetCode() async {
        if session?.leetcodeTitle == nil { leetcodeState = .loading }
        do {
            session = try await store.refreshLeetCode()
            leetcodeState = .loaded
        } catch {
            // Keep a previously stored problem visible even if the refresh failed.
            leetcodeState = session?.leetcodeTitle == nil ? .failed("Couldn't reach LeetCode.") : .loaded
        }
    }

    func openLeetCode() {
        NSWorkspace.shared.open(session?.leetcodeURL ?? LeetCodeService.fallbackURL)
    }

    func setLeetCodeSolved(_ solved: Bool) {
        do {
            try store.sessions.setLeetCodeCompleted(solved, for: day)
            reloadLocal()
            // Move straight on to the next unfinished task.
            if solved, !(session?.javaCompleted ?? false) { show(.java) }
        } catch {
            errorMessage = "Couldn't save LeetCode progress: \(error.localizedDescription)"
        }
    }

    func shiftMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = next
        reloadLocal()
    }
}
