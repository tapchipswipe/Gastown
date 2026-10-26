import AppKit
import SwiftUI

/// Shared look & feel: Vorssaint liquid-glass styling, brand colors, and materials.
public enum Theme {
    /// Near-black background behind the brand mark. Neutral greys into black, no
    /// colour cast, with just a hint of depth so panels do not read as flat.
    public static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.12),
                 Color(white: 0.05),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let accent = Color(red: 0.22, green: 0.54, blue: 0.98)
}

public enum PanelMetricColor {
    public static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    public static func cyan(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.43, blue: 0.54) : .cyan
    }

    public static func mint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.40) : .mint
    }

    public static func yellow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.56, green: 0.36, blue: 0.00) : .yellow
    }

    public static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    public static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    public static func purple(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.55, green: 0.15, blue: 0.70) : .purple
    }
}

public enum PanelSurface {
    public static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    public static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    public static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    public static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }

    public static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    public static func raisedBorder(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.22 : 0.07)
            : Color.white.opacity(raised ? 0.32 : 0.16)
    }

    public static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    public static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

public struct HUDBackdrop: View {
    public enum Contrast {
        case standard
        case high
    }

    public var cornerRadius: CGFloat = 0
    public var contrast: Contrast = .standard
    public var opacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = 0, contrast: Contrast = .standard, opacity: Double = 1) {
        self.cornerRadius = cornerRadius
        self.contrast = contrast
        self.opacity = opacity
    }

    private var materialOpacity: Double {
        reduceTransparency ? 1 : min(max(opacity, 0), 1)
    }

    private var plateOpacity: Double {
        guard contrast == .high, !reduceTransparency else { return 0 }
        return colorScheme == .dark ? 0.55 : 0.5
    }

    public var body: some View {
        classicBackdrop
    }

    @ViewBuilder
    private var classicBackdrop: some View {
        HUDBackdropMaterial(cornerRadius: cornerRadius, opacity: materialOpacity)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .opacity(plateOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
            )
    }
}

private struct HUDBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.alphaValue = CGFloat(opacity)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

public extension View {
    func panelCard(cornerRadius: CGFloat = 14, interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(cornerRadius: cornerRadius, interactive: interactive, padded: padded))
    }

    func glassBackdrop(cornerRadius: CGFloat = 16) -> some View {
        background(HUDBackdrop(cornerRadius: cornerRadius, contrast: .standard))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct PanelCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var interactive: Bool = true
    var padded: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padded ? 12 : 0)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .bold))
        .kerning(0.6)
        .foregroundStyle(.secondary)
}

public struct DisclosureHeaderRow<Label: View>: View {
    @Binding private var isExpanded: Bool
    private let label: () -> Label

    public init(isExpanded: Binding<Bool>, @ViewBuilder label: @escaping () -> Label) {
        self._isExpanded = isExpanded
        self.label = label
    }

    public var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                label()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }
}
