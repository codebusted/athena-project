import SwiftUI

enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.055)
    static let border = Color(white: 0.15)
    static let green = Color(red: 0.24, green: 0.86, blue: 0.47)
    static let greenDim = Color(red: 0.24, green: 0.86, blue: 0.47).opacity(0.3)
    static let text = Color(white: 0.93)
    static let secondary = Color(white: 0.55)
    static let tertiary = Color(white: 0.32)
    static let red = Color(red: 0.96, green: 0.42, blue: 0.42)
    static let amber = Color(red: 0.96, green: 0.76, blue: 0.3)

    // Type scale (points). Slightly larger than macOS defaults for at-a-glance reading.
    static let title = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 15)
    static let small = Font.system(size: 13)
    static let tiny = Font.system(size: 12)
    static let mono = Font.system(size: 16, design: .monospaced)
    static let monoSmall = Font.system(size: 14, design: .monospaced)
    static let label = Font.system(size: 12, weight: .semibold, design: .monospaced)

    static func difficultyColor(_ difficulty: String?) -> Color {
        switch difficulty?.lowercased() {
        case "easy": green
        case "medium": amber
        case "hard": red
        default: secondary
        }
    }
}

struct Card<Content: View>: View {
    let label: String
    var trailing: String?
    var trailingColor: Color = Theme.secondary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label).font(Theme.label).foregroundStyle(Theme.secondary).tracking(1.2)
                Spacer()
                if let trailing {
                    Text(trailing).font(Theme.label).foregroundStyle(trailingColor)
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(Color.black)
            .background(isEnabled ? Theme.green.opacity(configuration.isPressed ? 0.75 : 1) : Theme.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(Theme.green.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.greenDim, lineWidth: 1))
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body)
            .foregroundStyle(Theme.secondary.opacity(configuration.isPressed ? 0.6 : 1))
    }
}

struct CodeBlock: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }
}
