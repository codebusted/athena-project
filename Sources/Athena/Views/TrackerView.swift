import AthenaCore
import SwiftUI

struct TrackerView: View {
    let model: DashboardViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        Card(label: "PROGRESS") {
            VStack(alignment: .leading, spacing: 16) {
                stats
                calendar
                HStack {
                    legend
                    Spacer()
                    Button("Java learnings") { model.showingLearnings = true }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat("\(model.streak)", "streak")
            stat("\(model.bestStreak)", "best")
            stat("\(model.totals.leetcode)", "leetcode")
            stat("\(model.totals.java)", "java")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .monospaced))
            Text(label).font(Theme.small).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendar: some View {
        VStack(spacing: 8) {
            HStack {
                Button("‹") { model.shiftMonth(-1) }.buttonStyle(LinkButtonStyle())
                Spacer()
                Text(model.monthTitle).font(Theme.monoSmall)
                Spacer()
                Button("›") { model.shiftMonth(1) }.buttonStyle(LinkButtonStyle())
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(Theme.tiny).foregroundStyle(Theme.tertiary)
                }
                ForEach(0..<model.monthLeadingBlanks, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(model.monthDays) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: AthenaStore.MonthDay) -> some View {
        let isToday = day.date == model.day
        let fill: Color = switch day.completed {
        case 2: Theme.green
        case 1: Theme.greenDim
        default: Color(white: 0.09)
        }
        return Text("\(day.dayOfMonth)")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(day.completed == 2 ? Color.black : Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isToday ? Theme.green : .clear, lineWidth: 1))
            .help(day.completed == 2 ? "Both done" : day.completed == 1 ? "1 of 2 done" : "")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(Theme.green, "both done")
            legendItem(Theme.greenDim, "one done")
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(Theme.small).foregroundStyle(Theme.tertiary)
        }
    }

    private var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

struct LearningsView: View {
    let summary: LearningSummary?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Java learnings").font(Theme.title)
                Spacer()
                Button("Close", action: onClose).buttonStyle(LinkButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let summary, summary.totalAttempts > 0 {
                        overview(summary)
                        group("Strong", summary.strong, Theme.green)
                        group("Needs more work", summary.needsWork, Theme.amber)
                        group("Recently practised", summary.recent, Theme.text)
                        topicLines(summary.lines)
                        if !summary.untouched.isEmpty {
                            group("Not started yet", summary.untouched, Theme.tertiary)
                        }
                    } else {
                        Text("No graded Java exercises yet. Finish today's Java Daily to start building your profile.")
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding([.horizontal, .bottom], 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 600)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
    }

    private func overview(_ s: LearningSummary) -> some View {
        let accuracy = s.overallAccuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return Text("\(s.totalAttempts) graded exercises · \(accuracy) correct overall")
            .font(Theme.monoSmall).foregroundStyle(Theme.secondary)
    }

    @ViewBuilder private func group(_ title: String, _ items: [String], _ color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased()).font(Theme.label).foregroundStyle(Theme.secondary).tracking(1)
                ForEach(items, id: \.self) { Text("• \($0)").foregroundStyle(color) }
            }
        }
    }

    private func topicLines(_ lines: [LearningSummary.Line]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BY TOPIC").font(Theme.label).foregroundStyle(Theme.secondary).tracking(1)
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(line.topic).font(.system(size: 16, weight: .medium))
                        Spacer()
                        Text(line.status.rawValue).font(Theme.monoSmall).foregroundStyle(color(for: line.status))
                    }
                    Text(line.detail).font(Theme.small).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func color(for status: TopicStatus) -> Color {
        switch status {
        case .strong, .good: Theme.green
        case .improving: Theme.amber
        case .needsPractice: Theme.red
        case .new: Theme.tertiary
        }
    }
}
