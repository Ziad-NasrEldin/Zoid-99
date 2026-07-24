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
    enum Duration {
        static let press = 0.10
        static let hover = 0.14
        static let disclosure = 0.18
        static let state = 0.20
        static let page = 0.22
        static let exit = 0.14
        static let reduced = 0.08
    }

    enum Stagger {
        static let step = 0.03
        static let maximumDelay = 0.18
    }

    let reduceMotion: Bool
    var pressScale: CGFloat { reduceMotion ? 1 : 0.98 }
    var spatialOffset: CGFloat { reduceMotion ? 0 : 7 }
    var spatialAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: Duration.state)
    }
    var stateAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? Duration.reduced : Duration.state)
    }
    var opacityAnimation: Animation {
        .easeOut(duration: reduceMotion ? Duration.reduced : Duration.disclosure)
    }
    var pageAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? Duration.reduced : Duration.page)
    }

    func staggerDelay(index: Int) -> Double {
        guard !reduceMotion else { return 0 }
        return min(Double(max(index, 0)) * Stagger.step, Stagger.maximumDelay)
    }
}

struct SumiButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
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
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: SumiMotion.Duration.press),
                value: configuration.isPressed
            )
    }
}

struct SumiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? configuration.isPressed ? 0.72 : 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: SumiMotion.Duration.press),
                value: configuration.isPressed
            )
    }
}

struct SumiCheckboxStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Rectangle()
                        .fill(configuration.isOn ? SumiColor.ink : SumiColor.paper)
                    Rectangle()
                        .stroke(configuration.isOn ? SumiColor.ink : SumiColor.mutedInk, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SumiColor.paper)
                            .transition(.opacity)
                    }
                }
                .frame(width: 15, height: 15)
                configuration.label
                    .font(SumiFont.body(13))
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.42)
            .animation(SumiMotion(reduceMotion: reduceMotion).stateAnimation, value: configuration.isOn)
        }
        .buttonStyle(SumiPressStyle())
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct SumiFieldModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(SumiFont.body(13))
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(SumiColor.paper)
            .overlay(Rectangle().stroke(isHovering ? SumiColor.sealDeep : SumiColor.ink, lineWidth: 1))
            .onHover { isHovering = $0 }
            .animation(
                .easeOut(duration: reduceMotion ? SumiMotion.Duration.reduced : SumiMotion.Duration.hover),
                value: isHovering
            )
    }
}

struct SumiSelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

enum SumiSelectionCursor {
    static func movedIndex(current: Int, count: Int, direction: MoveCommandDirection) -> Int {
        guard count > 0 else { return 0 }
        switch direction {
        case .down, .right: return min(current + 1, count - 1)
        case .up, .left: return max(current - 1, 0)
        default: return current
        }
    }
}

struct SumiSelect<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    @Binding var selection: Value
    let options: [SumiSelectOption<Value>]
    var accessibilityLabel: String
    var width: CGFloat?

    @State private var isOpen = false
    @State private var focusedIndex = 0

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                focusedIndex = options.firstIndex(where: { $0.value == selection }) ?? 0
                isOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .font(SumiFont.body(12))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(SumiMotion(reduceMotion: reduceMotion).stateAnimation, value: isOpen)
                }
                .padding(.horizontal, 10)
                .frame(width: width, alignment: .leading)
                .frame(minHeight: 34)
                .background(SumiColor.paper)
                .overlay(Rectangle().stroke(isOpen ? SumiColor.ink : SumiColor.rule, lineWidth: 1))
            }
            .buttonStyle(SumiPressStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(selectedTitle)
            .accessibilityHint("Opens a list of choices")

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            selection = option.value
                            isOpen = false
                        } label: {
                            HStack(spacing: 9) {
                                Rectangle()
                                    .fill(option.value == selection ? SumiColor.seal : Color.clear)
                                    .frame(width: 2, height: 18)
                                Text(option.title)
                                    .font(SumiFont.body(12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if option.value == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .foregroundStyle(option.value == selection ? SumiColor.paper : SumiColor.ink)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 32)
                            .background(
                                option.value == selection
                                    ? SumiColor.ink
                                    : index == focusedIndex ? SumiColor.mist : SumiColor.paper
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option.value == selection ? [.isSelected] : [])
                    }
                }
                .padding(4)
                .frame(width: width)
                .background(SumiColor.paper)
                .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
                .shadow(color: SumiColor.ink.opacity(0.16), radius: 8, x: 0, y: 5)
                .offset(y: 38)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(
                            with: .offset(y: SumiMotion(reduceMotion: reduceMotion).spatialOffset)
                        ),
                        removal: .opacity
                    )
                )
                .zIndex(100)
            }
        }
        .fixedSize(horizontal: width != nil, vertical: true)
        .zIndex(isOpen ? 100 : 0)
        .animation(SumiMotion(reduceMotion: reduceMotion).opacityAnimation, value: isOpen)
        .onMoveCommand { direction in
            guard isOpen else { return }
            focusedIndex = SumiSelectionCursor.movedIndex(
                current: focusedIndex,
                count: options.count,
                direction: direction
            )
        }
        .onKeyPress(.return) {
            guard isOpen, options.indices.contains(focusedIndex) else { return .ignored }
            selection = options[focusedIndex].value
            isOpen = false
            return .handled
        }
        .onKeyPress(.space) {
            guard isOpen, options.indices.contains(focusedIndex) else { return .ignored }
            selection = options[focusedIndex].value
            isOpen = false
            return .handled
        }
        .onExitCommand { isOpen = false }
    }
}

struct SumiStepper: View {
    let title: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(SumiFont.body(12))
            HStack(spacing: 0) {
                Button(action: decrement) {
                    Image(systemName: "minus").frame(width: 24, height: 24)
                }
                .buttonStyle(SumiPressStyle())
                .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
                Button(action: increment) {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(SumiPressStyle())
                .overlay(Rectangle().stroke(SumiColor.ink, lineWidth: 1))
            }
            .font(.system(size: 9, weight: .semibold))
        }
        .accessibilityElement(children: .contain)
    }
}

struct SumiConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CONFIRM ACTION")
                .font(SumiFont.meta(10))
                .tracking(1.8)
                .foregroundStyle(SumiColor.sealDeep)
            Text(title)
                .font(SumiFont.display(26))
            Text(message)
                .font(SumiFont.body())
                .foregroundStyle(SumiColor.mutedInk)
            Divider().overlay(SumiColor.ink)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(SumiButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .buttonStyle(SumiButtonStyle(urgent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 430)
        .background(SumiColor.paper)
        .accessibilityElement(children: .contain)
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
            .sumiStateMotion("\(text)-\(urgent)")
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

private struct SumiStateMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(.opacity)
            .animation(SumiMotion(reduceMotion: reduceMotion).stateAnimation, value: value)
    }
}

private struct SumiCollectionMotionModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ids: [ID]

    func body(content: Content) -> some View {
        content
            .animation(SumiMotion(reduceMotion: reduceMotion).spatialAnimation, value: ids)
    }
}

private struct SumiPageMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(.opacity)
            .animation(SumiMotion(reduceMotion: reduceMotion).pageAnimation, value: value)
    }
}

private struct SumiRowTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .offset(y: SumiMotion(reduceMotion: false).spatialOffset))
        )
    }
}

private struct SumiHoverFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .opacity(isHovering ? 0.9 : 1)
            .offset(y: isHovering && !reduceMotion ? -1 : 0)
            .onHover { isHovering = $0 }
            .animation(
                .easeOut(duration: reduceMotion ? SumiMotion.Duration.reduced : SumiMotion.Duration.hover),
                value: isHovering
            )
    }
}

extension View {
    func sumiField() -> some View {
        modifier(SumiFieldModifier())
    }

    func sumiPage() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SumiColor.paper)
            .foregroundStyle(SumiColor.ink)
            .tint(SumiColor.sealDeep)
            .toggleStyle(SumiCheckboxStyle())
    }

    func sumiStateMotion<Value: Equatable>(_ value: Value) -> some View {
        modifier(SumiStateMotionModifier(value: value))
    }

    func sumiCollectionMotion<ID: Hashable>(_ ids: [ID]) -> some View {
        modifier(SumiCollectionMotionModifier(ids: ids))
    }

    func sumiPageMotion<Value: Equatable>(_ value: Value) -> some View {
        modifier(SumiPageMotionModifier(value: value))
    }

    func sumiRowTransition() -> some View {
        modifier(SumiRowTransitionModifier())
    }

    func sumiHoverFeedback() -> some View {
        modifier(SumiHoverFeedbackModifier())
    }
}
