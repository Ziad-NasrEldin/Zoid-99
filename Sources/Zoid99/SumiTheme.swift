import SwiftUI

enum SumiColor {
    static let ink = Color(red: 13 / 255, green: 10 / 255, blue: 10 / 255)
    static let paper = Color.white
    static let softPaper = Color(white: 250 / 255)
    static let mist = Color(white: 245 / 255)
    static let paleRule = Color(white: 237 / 255)
    static let rule = Color(white: 224 / 255)
    static let mutedInk = Color(red: 84 / 255, green: 85 / 255, blue: 84 / 255)
    static let seal = Color(red: 194 / 255, green: 58 / 255, blue: 46 / 255)
    static let sealDeep = Color(red: 143 / 255, green: 33 / 255, blue: 26 / 255)
    static let sealWash = Color(red: 245 / 255, green: 229 / 255, blue: 227 / 255)
    static let healthy = Color(red: 47 / 255, green: 58 / 255, blue: 47 / 255)
}

enum SumiFont {
    static func display(_ size: CGFloat) -> Font { .custom("Times New Roman", size: size) }
    static func body(_ size: CGFloat = 14) -> Font { .custom("Hiragino Mincho ProN", size: size) }
    static func meta(_ size: CGFloat = 11) -> Font {
        .custom("Times New Roman", size: size).weight(.semibold)
    }
}

struct SumiMotion {
    static let pressDuration = 0.15
    static let hoverDuration = 0.18
    static let disclosureDuration = 0.16
    static let standardDuration = 0.20

    let reduceMotion: Bool
    var pressScale: CGFloat { reduceMotion ? 1 : 0.98 }
    var standardAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: Self.standardDuration) }
    var opacityAnimation: Animation { .easeOut(duration: Self.disclosureDuration) }
}

struct SumiButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var primary = false
    var urgent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SumiFont.meta(12))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(primary ? SumiColor.paper : urgent ? SumiColor.sealDeep : SumiColor.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(primary ? SumiColor.ink : urgent ? SumiColor.sealWash : SumiColor.paper)
            .overlay(Rectangle().stroke(urgent ? SumiColor.seal : SumiColor.ink, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: SumiMotion.pressDuration), value: configuration.isPressed)
    }
}

struct StateLabel: View {
    let text: String
    var urgent = false

    var body: some View {
        Text(text.uppercased())
            .font(SumiFont.meta(10))
            .tracking(1)
            .foregroundStyle(urgent ? SumiColor.sealDeep : SumiColor.mutedInk)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(urgent ? SumiColor.sealWash : SumiColor.mist)
            .overlay(Rectangle().stroke(urgent ? SumiColor.seal : SumiColor.rule, lineWidth: 1))
            .accessibilityLabel("State: \(text)")
    }
}

struct LedgerHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(SumiFont.meta())
                .tracking(2)
                .foregroundStyle(SumiColor.sealDeep)
            Text(title)
                .font(SumiFont.display(32))
                .foregroundStyle(SumiColor.ink)
            Text(subtitle)
                .font(SumiFont.body())
                .foregroundStyle(SumiColor.mutedInk)
        }
    }
}

extension View {
    func sumiPage() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SumiColor.paper)
            .foregroundStyle(SumiColor.ink)
    }
}
