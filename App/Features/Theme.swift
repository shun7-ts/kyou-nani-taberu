import SwiftUI
import UIKit
import CoreText

/// Bundled Japanese typography with the same semantic sizes and Dynamic Type scaling.
enum AppFont {
    static let names = ["NotoSansJP-Regular", "NotoSansJP-Medium", "NotoSansJP-Bold"]
    static func register() {
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "otf", subdirectory: "fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    static func custom(_ size: CGFloat, relativeTo style: Font.TextStyle, medium: Bool = false) -> Font {
        .custom(medium ? names[1] : names[0], size: size, relativeTo: style)
    }
    static var largeTitle: Font { custom(34, relativeTo: .largeTitle) }
    static var title: Font { custom(28, relativeTo: .title) }
    static var title2: Font { custom(22, relativeTo: .title2) }
    static var title3: Font { custom(20, relativeTo: .title3) }
    static var headline: Font { custom(17, relativeTo: .headline, medium: true) }
    static var body: Font { custom(17, relativeTo: .body) }
    static var callout: Font { custom(16, relativeTo: .callout) }
    static var subheadline: Font { custom(15, relativeTo: .subheadline) }
    static var footnote: Font { custom(13, relativeTo: .footnote) }
    static var caption: Font { custom(12, relativeTo: .caption) }
    static var caption2: Font { custom(11, relativeTo: .caption2) }
    static func configureNativeControls() {
        guard let regular = UIFont(name: names[0], size: 17), let bold = UIFont(name: names[2], size: 17) else { return }
        UINavigationBar.appearance().titleTextAttributes = [.font: bold]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: bold.withSize(34)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: UIFontMetrics(forTextStyle: .body).scaledFont(for: regular)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: regular.withSize(10)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: bold.withSize(10)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: regular.withSize(13)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: bold.withSize(13)], for: .selected)
    }
}

enum AppTheme {
    static let background = adaptive(0xFFFCF8, 0x181311)
    static let surface = adaptive(0xFFFDFB, 0x241B18)
    static let accent = adaptive(0xCF413A, 0xFF8B80)
    static let accentFill = adaptive(0xD23F3A, 0xD23F3A)
    static let accentPressed = adaptive(0xBF342F, 0xBF342F)
    static let mealAddFill = adaptive(0xE65445, 0xE65445)
    static let tabAccent = adaptive(0xF23829, 0xF23829)
    static let onAccent = Color.white
    static let border = adaptive(0xE5DDD6, 0x4D3931)
    static let shadowInk = adaptive(0x52453D, 0x000000)
    static let illustration = adaptive(0xFF5652, 0xFF8B80)
    static let accentSoft = adaptive(0xFFECE6, 0x402521)
    static let secondary = adaptive(0x77665E, 0xC0AEA4)
    static let text = adaptive(0x2E211C, 0xF7F0EB)
    static let productName = adaptive(0x161616, 0xFAFAFA)
    static let warning = adaptive(0x965B00, 0xF2BD66)
    static let success = adaptive(0x24634A, 0x8ED1AD)
    static let readyBadge = Color(red: 36 / 255.0, green: 99 / 255.0, blue: 74 / 255.0)
    static let danger = adaptive(0xA03B35, 0xF28A83)
    private static func adaptive(_ light: Int, _ dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}
/// A single 44pt minimum after padding prevents caller/style height double-counting.
struct CoralPrimaryButtonStyle: ButtonStyle {
    var fill: Color = AppTheme.accentFill
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(minHeight: 44)
            .foregroundStyle(isEnabled ? AppTheme.onAccent : AppTheme.secondary)
            .background(isEnabled ? (configuration.isPressed ? AppTheme.accentPressed : fill)
                : AppTheme.secondary.opacity(0.12), in: Capsule())
    }
}

struct FontLicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt", subdirectory: "fonts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "ライセンスを読み込めません" }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Noto Sans JP").font(AppFont.title2.bold())
                Text("Copyright 2014–2021 Adobe. Reserved Font Name: Source.").font(AppFont.caption)
                Link("公式配布元", destination: URL(string: "https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF/JP")!)
                Text(license).font(AppFont.caption).textSelection(.enabled)
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }.background(AppTheme.background).navigationTitle("フォントのライセンス").navigationBarTitleDisplayMode(.inline)
    }
}

/// Native text and restrained vector decorations for the paired home entries.
struct IllustratedIngredientLabel: View {
    let title: String
    var compact = false
    var body: some View { MealEntryLabel(title: title, ingredient: true, compact: compact) }
}
struct IllustratedRecipeLabel: View {
    var compact = false
    var body: some View { MealEntryLabel(title: "料理から\n選ぶ", ingredient: false, compact: compact) }
}
private struct MealEntryLabel: View {
    let title: String
    let ingredient: Bool
    let compact: Bool
    private let coral = Color(red: 230 / 255.0, green: 84 / 255.0, blue: 69 / 255.0)
    var body: some View {
        Text(title).font((compact ? AppFont.subheadline : AppFont.body).weight(.semibold))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.horizontal, compact ? 29 : 46)
            .padding(.vertical, 10).frame(minHeight: 78)
            .foregroundStyle(coral)
            .background {
                Group {
                    if ingredient {
                        ConnectedIngredientOutline(compact: compact).fill(Color.white)
                        ConnectedIngredientOutline(compact: compact).stroke(coral,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        GeometryReader { geometry in
                            let scale: CGFloat = compact ? 0.75 : 1
                            // The white tomato overlaps the carrot and masks the rear contour.
                            OpenMojiTomatoIcon().fill(Color.white)
                                .overlay { OpenMojiTomatoIcon().stroke(coral,
                                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)) }
                                .frame(width: 32.4 * scale, height: 32.4 * scale)
                                .position(x: 20.0788 * scale, y: geometry.size.height / 2 + 0.0094 * scale)
                        }
                    }
                    else {
                        ConnectedCutleryOutline(compact: compact, surfaceOnly: true).fill(Color.white)
                        ConnectedCutleryOutline(compact: compact).stroke(coral,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }.accessibilityHidden(true).allowsHitTesting(false)
            }
            .contentShape(Rectangle()).accessibilityElement(children: .ignore)
            .accessibilityLabel(title.replacingOccurrences(of: "\n", with: ""))
    }
}
private struct ConnectedIngredientOutline: Shape {
    var compact = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s: CGFloat = compact ? 0.75 : 1
        let c = rect.midY, t = rect.minY + 5, b = rect.maxY - 5
        let l = 14 * s, r = rect.maxX - 14 * s, radius: CGFloat = 18
        // The upper edge stops at the carrot; the lower edge meets the tomato.
        p.move(to: CGPoint(x: l, y: c - 16 * s))
        p.addLine(to: CGPoint(x: l, y: t + radius))
        p.addQuadCurve(to: CGPoint(x: l + radius, y: t), control: CGPoint(x: l, y: t))
        p.addLine(to: CGPoint(x: r - radius, y: t))
        p.addQuadCurve(to: CGPoint(x: r, y: t + radius), control: CGPoint(x: r, y: t))
        p.addLine(to: CGPoint(x: r, y: c - 8 * s))
        // Pointed outer tips and a shallow V, without extra fin details.
        p.addCurve(to: CGPoint(x: r + 13 * s, y: c - 15 * s),
                   control1: CGPoint(x: r + 5 * s, y: c - 11 * s), control2: CGPoint(x: r + 8 * s, y: c - 13 * s))
        p.addLine(to: CGPoint(x: r + 5 * s, y: c))
        p.addLine(to: CGPoint(x: r + 13 * s, y: c + 15 * s))
        p.addCurve(to: CGPoint(x: r, y: c + 8 * s),
                   control1: CGPoint(x: r + 8 * s, y: c + 13 * s), control2: CGPoint(x: r + 5 * s, y: c + 11 * s))
        p.addLine(to: CGPoint(x: r, y: b - radius))
        p.addQuadCurve(to: CGPoint(x: r - radius, y: b), control: CGPoint(x: r, y: b))
        p.addLine(to: CGPoint(x: l + radius, y: b))
        p.addQuadCurve(to: CGPoint(x: l, y: b - radius), control: CGPoint(x: l, y: b))
        p.addLine(to: CGPoint(x: l, y: min(c + 32 * s, b - radius)))
        // Join the overlapping tomato's lower tangent.
        p.addCurve(to: CGPoint(x: 20 * s, y: c + 10.8 * s),
                   control1: CGPoint(x: l, y: c + 10.8 * s), control2: CGPoint(x: 17 * s, y: c + 10.8 * s))
        // Joined carrot leaf/body silhouette, slanting to the lower left.
        p.move(to: CGPoint(x: l, y: c - 16 * s))
        p.addLine(to: CGPoint(x: 16 * s, y: c - 22 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: c - 19 * s))
        p.addLine(to: CGPoint(x: 22 * s, y: c - 22 * s))
        p.addQuadCurve(to: CGPoint(x: 22 * s, y: c - 14 * s), control: CGPoint(x: 26 * s, y: c - 17 * s))
        p.addQuadCurve(to: CGPoint(x: 3 * s, y: c + 9 * s), control: CGPoint(x: 17 * s, y: c - 3 * s))
        p.addQuadCurve(to: CGPoint(x: 0, y: c + 6 * s), control: CGPoint(x: -2 * s, y: c + 14 * s))
        p.addQuadCurve(to: CGPoint(x: 12 * s, y: c - 12 * s), control: CGPoint(x: 2 * s, y: c - 1 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: c - 15 * s))
        p.addLine(to: CGPoint(x: l, y: c - 16 * s))
        return p
    }
}
private struct ConnectedCutleryOutline: Shape {
    var compact = false
    var surfaceOnly = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s: CGFloat = compact ? 0.75 : 1
        let t = rect.minY + 5, b = rect.maxY - 5, c = rect.midY
        let l = 14 * s, r = rect.maxX - 14 * s
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        // Upper frame, knife's outer edge, lower frame, fork's outer left edge.
        p.move(to: point(l + 12 * s, t))
        p.addLine(to: point(r - 12 * s, t))
        p.addLine(to: point(r + 6 * s, t))
        p.addLine(to: point(r + 6 * s, b - 7 * s))
        p.addQuadCurve(to: point(r - 2 * s, b), control: point(r + 6 * s, b))
        p.addLine(to: point(l + 5 * s, b))
        p.addQuadCurve(to: point(l - 1 * s, b - 7 * s), control: point(l - 1 * s, b))
        p.addLine(to: point(l - 1 * s, c + 3 * s))
        p.addCurve(to: point(l - 9 * s, t + 18 * s),
                   control1: point(l - 1 * s, c - 6 * s), control2: point(l - 9 * s, c - 5 * s))
        p.addLine(to: point(l - 9 * s, t))
        if surfaceOnly {
            // Fill only the outer contour. Open handle strokes would close into holes.
            p.closeSubpath()
            return p
        }
        // Three fork prongs. All junctions are shared endpoints, never overlaid strokes.
        p.move(to: point(l - 4 * s, t)); p.addLine(to: point(l - 4 * s, t + 16 * s))
        p.addQuadCurve(to: point(l + 1 * s, t + 16 * s), control: point(l - 1.5 * s, t + 20 * s))
        p.addLine(to: point(l + 1 * s, t))
        p.move(to: point(l + 6 * s, t)); p.addLine(to: point(l + 6 * s, t + 16 * s))
        p.addQuadCurve(to: point(l + 12 * s, t + 16 * s), control: point(l + 9 * s, t + 20 * s))
        p.addLine(to: point(l + 12 * s, t))
        p.move(to: point(l + 12 * s, t + 16 * s))
        p.addCurve(to: point(l + 5 * s, c + 3 * s),
                   control1: point(l + 12 * s, c - 5 * s), control2: point(l + 5 * s, c - 6 * s))
        p.addLine(to: point(l + 5 * s, b))
        // Knife blade and inner handle join the same upper/lower frame endpoints.
        p.move(to: point(r + 6 * s, t))
        p.addCurve(to: point(r - 9 * s, c - 2 * s),
                   control1: point(r - 3 * s, t + 6 * s), control2: point(r - 11 * s, c - 18 * s))
        p.addQuadCurve(to: point(r - 2 * s, c + 4 * s), control: point(r - 9 * s, c + 4 * s))
        p.addLine(to: point(r - 2 * s, b))
        return p
    }
}

// OpenMoji contributors, CC BY-SA 4.0. SVG path conversions; scaled/recolored.
// Sources and license: design/icons/openmoji/ (version 15.1.0).
private struct OpenMojiCarrotIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 51.276400, y: 27.440500))
        p.addCurve(to: CGPoint(x: 47.053900, y: 34.012400), control1: CGPoint(x: 50.513500, y: 29.544200), control2: CGPoint(x: 49.048000, y: 31.912000))
        p.addLine(to: CGPoint(x: 25.549900, y: 56.662800))
        p.addCurve(to: CGPoint(x: 18.541700, y: 50.917100), control1: CGPoint(x: 17.737700, y: 64.891400), control2: CGPoint(x: 12.004400, y: 60.191000))
        p.addLine(to: CGPoint(x: 36.536400, y: 25.389600))
        p.addCurve(to: CGPoint(x: 42.257700, y: 19.897700), control1: CGPoint(x: 38.235500, y: 22.979200), control2: CGPoint(x: 40.314200, y: 21.051800))
        p.addQuadCurve(to: CGPoint(x: 47.137200, y: 16.959200), control: CGPoint(x: 45, y: 19.897700))
        p.addCurve(to: CGPoint(x: 48.384400, y: 13.636100), control1: CGPoint(x: 47.310800, y: 15.732600), control2: CGPoint(x: 47.819500, y: 14.586600))
        p.addCurve(to: CGPoint(x: 50.387400, y: 11.045600), control1: CGPoint(x: 49.310400, y: 12.078100), control2: CGPoint(x: 50.387400, y: 11.045600))
        p.addCurve(to: CGPoint(x: 52.222900, y: 14.694700), control1: CGPoint(x: 50.387400, y: 11.045600), control2: CGPoint(x: 52.248200, y: 12.051400))
        p.addCurve(to: CGPoint(x: 57.088000, y: 12.057200), control1: CGPoint(x: 54.579900, y: 12.427900), control2: CGPoint(x: 57.088000, y: 12.057200))
        p.addCurve(to: CGPoint(x: 55.175000, y: 17.248000), control1: CGPoint(x: 57.088000, y: 12.057200), control2: CGPoint(x: 57.078500, y: 14.588900))
        p.addCurve(to: CGPoint(x: 56.770900, y: 17.261500), control1: CGPoint(x: 55.777500, y: 17.154000), control2: CGPoint(x: 56.312200, y: 17.172300))
        p.addCurve(to: CGPoint(x: 59.054700, y: 18.542000), control1: CGPoint(x: 58.305600, y: 17.541000), control2: CGPoint(x: 59.054700, y: 18.542000))
        p.addCurve(to: CGPoint(x: 53.667100, y: 22.606900), control1: CGPoint(x: 59.054700, y: 18.542000), control2: CGPoint(x: 56.800200, y: 21.683300))
        p.addCurve(to: CGPoint(x: 51.941200, y: 22.845500), control1: CGPoint(x: 53.022200, y: 22.800900), control2: CGPoint(x: 52.447900, y: 22.862300))
        p.addQuadCurve(to: CGPoint(x: 51.276400, y: 27.440500), control: CGPoint(x: 52.3, y: 25.2))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 72, y: rect.height / 72))
    }
}
private struct OpenMojiTomatoIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 50.307300, y: 19.346200))
        p.addCurve(to: CGPoint(x: 60.839700, y: 37.597500), control1: CGPoint(x: 56.681600, y: 23.402700), control2: CGPoint(x: 60.839700, y: 30.065700))
        p.addCurve(to: CGPoint(x: 35.824800, y: 59.979200), control1: CGPoint(x: 60.839700, y: 49.958600), control2: CGPoint(x: 49.640200, y: 59.979200))
        p.addCurve(to: CGPoint(x: 10.810000, y: 37.597500), control1: CGPoint(x: 22.009400, y: 59.979200), control2: CGPoint(x: 10.810000, y: 49.958600))
        p.addCurve(to: CGPoint(x: 20.945700, y: 19.603900), control1: CGPoint(x: 10.810000, y: 30.223000), control2: CGPoint(x: 14.796100, y: 23.681600))
        p.move(to: CGPoint(x: 46.324500, y: 15.848900))
        p.addCurve(to: CGPoint(x: 43.888800, y: 20.083900), control1: CGPoint(x: 45.940500, y: 17.231300), control2: CGPoint(x: 45.330800, y: 18.880000))
        p.addCurve(to: CGPoint(x: 26.817300, y: 20.083800), control1: CGPoint(x: 38.000000, y: 25.000000), control2: CGPoint(x: 30.251300, y: 23.287600))
        p.addCurve(to: CGPoint(x: 24.392700, y: 15.848800), control1: CGPoint(x: 25.456900, y: 18.800200), control2: CGPoint(x: 24.776600, y: 17.231300))
        p.addCurve(to: CGPoint(x: 24.030600, y: 11.679700), control1: CGPoint(x: 23.756300, y: 13.566700), control2: CGPoint(x: 24.030600, y: 11.679700))
        p.addCurve(to: CGPoint(x: 28.869000, y: 12.261200), control1: CGPoint(x: 24.030600, y: 11.679700), control2: CGPoint(x: 26.312700, y: 11.350600))
        p.addCurve(to: CGPoint(x: 31.491200, y: 13.665600), control1: CGPoint(x: 29.735800, y: 12.568400), control2: CGPoint(x: 30.635400, y: 13.018200))
        p.addCurve(to: CGPoint(x: 35.045900, y: 7.324100), control1: CGPoint(x: 31.973900, y: 10.297400), control2: CGPoint(x: 34.223100, y: 8.048200))
        p.addLine(to: CGPoint(x: 35.353100, y: 7.071800))
        p.addLine(to: CGPoint(x: 35.660300, y: 7.324100))
        p.addCurve(to: CGPoint(x: 39.215100, y: 13.665600), control1: CGPoint(x: 36.483200, y: 8.048300), control2: CGPoint(x: 38.732400, y: 10.297400))
        p.addCurve(to: CGPoint(x: 41.837200, y: 12.261200), control1: CGPoint(x: 40.070800, y: 13.018300), control2: CGPoint(x: 40.970500, y: 12.568500))
        p.addCurve(to: CGPoint(x: 46.675600, y: 11.679700), control1: CGPoint(x: 44.393600, y: 11.350600), control2: CGPoint(x: 46.675600, y: 11.679700))
        p.addCurve(to: CGPoint(x: 46.324500, y: 15.848900), control1: CGPoint(x: 46.675600, y: 11.679700), control2: CGPoint(x: 46.960900, y: 13.566800))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 72, y: rect.height / 72))
    }
}

extension IngredientUnit {
    var label: String {
        switch self {
        case .piece: "個"
        case .gram: "g"
        case .kilogram: "kg"
        case .milliliter: "ml"
        case .liter: "L"
        case .pack: "パック"
        case .bag: "袋"
        case .can: "缶"
        case .block: "丁"
        case .bunch: "束"
        case .stalk: "本"
        case .clove: "片"
        case .slice: "枚"
        case .serving: "膳"
        case .portion: "玉"
        case .tablespoon: "大さじ"
        case .teaspoon: "小さじ"
        }
    }
}
extension StorageMethod {
    var label: String {
        switch self { case .refrigerated: "冷蔵"; case .frozen: "冷凍"; case .roomTemperature: "常温" }
    }
}
extension RoughStockState {
    var label: String {
        switch self { case .available: "ある"; case .low: "少ない"; case .unavailable: "ない" }
    }
}
extension IngredientCategory {
    var label: String {
        switch self {
        case .staple: "麺・穀類"; case .vegetable: "野菜"; case .mushroom: "きのこ"
        case .meat: "肉"; case .fish: "魚"; case .eggDairy: "乳・卵"
        case .soyProduct: "大豆製品"; case .processed: "加工品"; case .seasoning: "調味料"; case .other: "その他"
        }
    }
}
extension ExpiryKind {
    var label: String {
        switch self { case .unspecified: "未指定"; case .bestBefore: "賞味期限"; case .useBy: "消費期限" }
    }
}
func amountLabel(_ item: InventoryItem) -> String {
    if item.stockMode == .rough { return item.roughState?.label ?? "要確認" }
    return "\((item.quantity ?? 0).formatted(.number.precision(.fractionLength(0...3))))\(item.unit?.label ?? "")"
}
func expiryLabel(_ item: InventoryItem) -> String {
    guard let expiry = item.expiresAt else { return "期限なし" }
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                               to: Calendar.current.startOfDay(for: expiry)).day ?? 0
    if days < 0 { return "期限切れ" }
    if days == 0 { return "今日まで" }
    if days == 1 { return "明日まで" }
    return expiry.formatted(.dateTime.month().day()) + "まで"
}

/// Keeps the filter name and current selection readable when text needs more width.
struct LabeledFilterMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    Text(label(selection)).foregroundStyle(AppTheme.text)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(AppFont.caption).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.accessibilityLabel(title).accessibilityValue(label(selection))
    }
}

struct MealPhotoEntry: Codable {
    let recipeKey: String
    let title: String
    let file: String
    let kind: String
    let creator: String
    let source: String
    let license: String
    let licenseURL: String
}
enum RecipeImageLibrary {
    static let entries: [MealPhotoEntry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "meal-images"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([MealPhotoEntry].self, from: data) else { return [] }
        return result
    }()
    private static let byKey = Dictionary(entries.map { ($0.recipeKey, $0) }, uniquingKeysWith: { first, _ in first })
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 12; cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    static func entry(for key: String?) -> MealPhotoEntry? { key.flatMap { byKey[$0] } }
    static func image(for key: String?) -> UIImage? {
        guard let key, let entry = byKey[key], !entry.file.contains("/"), !entry.file.contains("..") else { return nil }
        if let image = cache.object(forKey: key as NSString) { return image }
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("meal-images"),
              let image = UIImage(contentsOfFile: folder.appendingPathComponent(entry.file).path) else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
}
struct MealPhotoCreditsView: View {
    var body: some View {
        List {
            Section("食材アイコン") {
                Text("OpenMoji contributors · Carrot / Tomato / Mushroom / Beans / Sheaf of rice / Canned food").font(AppFont.subheadline)
                Link("OpenMoji 15.1.0", destination: URL(string: "https://github.com/hfg-gmuend/openmoji/tree/005bf5bc62392a9f90e1b6429c163d17610a791e")!)
                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                Text("トマトはコーラルに変更し、サイズと配置を調整。きのこ・豆・穀物・缶詰の線画は縮小して単色で表示。フォーク・ナイフ・人参・枠はSwiftUIの図形です。初期の人参素材の出典も保持しています。")
                    .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
            }
            Section {
                Text("料理のイメージです。盛り付けや付け合わせがレシピと異なる場合があります。")
                    .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
            }
            ForEach(RecipeImageLibrary.entries.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, id: \.recipeKey) { entry in
                Section(entry.title) {
                    Text(entry.kind == "generated" ? "AI生成画像" : entry.creator).font(AppFont.subheadline)
                    if let url = URL(string: entry.source), !entry.source.isEmpty { Link("写真の出典", destination: url) }
                    if let url = URL(string: entry.licenseURL), !entry.licenseURL.isEmpty {
                        Link(entry.license, destination: url)
                        Text("表示枠に合わせてトリミングしています。")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    } else if entry.kind == "free" {
                        Text(entry.license).font(AppFont.caption)
                    }
                }
            }
        }.navigationTitle("画像の出典").navigationBarTitleDisplayMode(.inline)
    }
}

struct RecipeMealImage: View {
    static let image: UIImage? = Bundle.main.url(forResource: "shared-meal", withExtension: "jpg")
        .flatMap { UIImage(contentsOfFile: $0.path) }
    let height: CGFloat
    var recipeKey: String? = nil
    var riceTopDown = false
    var body: some View {
        GeometryReader { geometry in
            if recipeKey == "plain_rice" {
                if riceTopDown, let illustration = RecipeImageLibrary.image(for: "plain_rice") {
                    Image(uiImage: illustration).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: height)
                } else {
                    RiceBowlIllustration(topDown: riceTopDown).frame(width: geometry.size.width, height: height)
                }
            } else {
                Image(uiImage: RecipeImageLibrary.image(for: recipeKey) ?? Self.image ?? UIImage(systemName: "fork.knife")!)
                    .resizable().scaledToFill().frame(width: geometry.size.width, height: height).clipped()
            }
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}


/// A small vector illustration keeps plain rice recognizable on the tray, even without a photo.
private struct RiceBowlIllustration: View {
    var topDown = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            if topDown {
                drawTopDown(context: context, size: size)
                return
            }
            context.scaleBy(x: size.width / 120, y: size.height / 110)
            let bowl = scheme == .dark ? Color(red: 0.40, green: 0.57, blue: 0.62) : Color(red: 0.70, green: 0.83, blue: 0.86)
            let ink = Color(red: 0.33, green: 0.51, blue: 0.56)
            context.fill(Path(ellipseIn: CGRect(x: 43, y: 96, width: 34, height: 5)), with: .color(ink.opacity(0.7)))
            var body = Path()
            body.move(to: CGPoint(x: 15, y: 48))
            body.addQuadCurve(to: CGPoint(x: 60, y: 97), control: CGPoint(x: 23, y: 93))
            body.addQuadCurve(to: CGPoint(x: 105, y: 48), control: CGPoint(x: 97, y: 93))
            body.closeSubpath()
            context.fill(body, with: .color(bowl))
            context.fill(Path(ellipseIn: CGRect(x: 15, y: 40, width: 90, height: 22)), with: .color(ink.opacity(0.35)))
            var rice = Path()
            rice.move(to: CGPoint(x: 18, y: 49))
            rice.addCurve(to: CGPoint(x: 60, y: 21), control1: CGPoint(x: 23, y: 29), control2: CGPoint(x: 40, y: 20))
            rice.addCurve(to: CGPoint(x: 102, y: 49), control1: CGPoint(x: 80, y: 20), control2: CGPoint(x: 97, y: 29))
            rice.addQuadCurve(to: CGPoint(x: 18, y: 49), control: CGPoint(x: 60, y: 65))
            context.fill(rice, with: .color(Color(red: 1, green: 0.99, blue: 0.94)))
            for (row, count) in [5, 9, 13, 15].enumerated() {
                for column in 0..<count {
                    let x = 60 + (Double(column) - Double(count - 1) / 2) * 5.6
                    let y = 28 + Double(row) * 6 + (column.isMultiple(of: 2) ? 0 : 1)
                    let grain = Path(ellipseIn: CGRect(x: -2, y: -0.9, width: 4, height: 1.8))
                        .applying(CGAffineTransform(rotationAngle: column.isMultiple(of: 2) ? -0.45 : 0.35)
                            .concatenating(CGAffineTransform(translationX: x, y: y)))
                    context.fill(grain, with: .color(Color(red: 0.83, green: 0.79, blue: 0.67).opacity(0.7)))
                }
            }
            var rim = Path()
            rim.move(to: CGPoint(x: 16, y: 49)); rim.addQuadCurve(to: CGPoint(x: 104, y: 49), control: CGPoint(x: 60, y: 73))
            context.stroke(rim, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var decoration = Path()
            decoration.move(to: CGPoint(x: 34, y: 70)); decoration.addQuadCurve(to: CGPoint(x: 86, y: 70), control: CGPoint(x: 60, y: 84))
            context.stroke(decoration, with: .color(Color.white.opacity(0.65)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }.accessibilityHidden(true)
    }

    private func drawTopDown(context original: GraphicsContext, size: CGSize) {
        var context = original
        let scale = min(size.width, size.height) / 200
        context.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 200 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let light = CGPoint(x: 70, y: 55)
        let rim = Path(ellipseIn: CGRect(x: 8, y: 8, width: 184, height: 184))
        let glaze = scheme == .dark
            ? [Color(red: 0.75, green: 0.84, blue: 0.84), Color(red: 0.43, green: 0.63, blue: 0.67)]
            : [Color(red: 0.96, green: 0.99, blue: 0.98), Color(red: 0.66, green: 0.81, blue: 0.83)]
        context.fill(rim, with: .radialGradient(Gradient(colors: glaze), center: light, startRadius: 15, endRadius: 175))
        context.stroke(rim, with: .color(Color(red: 0.36, green: 0.58, blue: 0.61).opacity(0.45)), lineWidth: 1)
        context.stroke(Path(ellipseIn: CGRect(x: 12, y: 12, width: 176, height: 176)),
            with: .color(.white.opacity(0.7)), lineWidth: 2)
        let well = Path(ellipseIn: CGRect(x: 22, y: 22, width: 156, height: 156))
        context.fill(well, with: .radialGradient(Gradient(colors: [Color(red: 0.99, green: 0.98, blue: 0.93),
            Color(red: 0.68, green: 0.75, blue: 0.72)]), center: light, startRadius: 30, endRadius: 140))

        // A gently irregular mound and overlapping filled grains avoid a sparse, patterned surface.
        var mound = Path()
        for point in 0..<160 {
            let angle = Double(point) * .pi * 2 / 160
            let radius = 73 + sin(angle * 13) * 0.9 + cos(angle * 19) * 0.6
            let p = CGPoint(x: 100 + cos(angle) * radius, y: 100 + sin(angle) * radius)
            if point == 0 { mound.move(to: p) } else { mound.addLine(to: p) }
        }
        mound.closeSubpath()
        context.fill(mound, with: .radialGradient(Gradient(colors: [.white, Color(red: 0.96, green: 0.94, blue: 0.86)]),
            center: CGPoint(x: 85, y: 80), startRadius: 15, endRadius: 95))
        context.clip(to: mound)
        for row in 0..<19 {
            for column in 0..<19 {
                let seed = Double(row * 41 + column * 17)
                let x = 24 + Double(column) * 8.4 + sin(seed * 1.7) * 2.5
                let y = 24 + Double(row) * 8.4 + cos(seed * 1.3) * 2.5
                guard hypot(x - 100, y - 100) < 77 else { continue }
                let length = 10.8 + sin(seed) * 1.6
                let width = 5.2 + cos(seed * 0.8) * 0.7
                let rotation = seed * 0.73
                let transform = CGAffineTransform(rotationAngle: rotation)
                    .concatenating(CGAffineTransform(translationX: x, y: y))
                var grain = Path()
                grain.move(to: CGPoint(x: -length / 2, y: 0))
                grain.addCurve(to: CGPoint(x: length / 2, y: 0),
                    control1: CGPoint(x: -length * 0.36, y: -width * 0.75), control2: CGPoint(x: length * 0.32, y: -width * 0.60))
                grain.addCurve(to: CGPoint(x: -length / 2, y: 0),
                    control1: CGPoint(x: length * 0.40, y: width * 0.65), control2: CGPoint(x: -length * 0.30, y: width * 0.65))
                grain.closeSubpath()
                let placed = grain.applying(transform)
                context.fill(placed.applying(CGAffineTransform(translationX: 0.4, y: 0.7)),
                    with: .color(Color(red: 0.69, green: 0.65, blue: 0.52).opacity(0.20)))
                context.fill(placed, with: .color(Color(red: 1, green: 0.99, blue: 0.95)))
                var shine = Path()
                shine.move(to: CGPoint(x: -length * 0.28, y: -width * 0.13))
                shine.addQuadCurve(to: CGPoint(x: length * 0.25, y: -width * 0.16), control: CGPoint(x: 0, y: -width * 0.37))
                context.stroke(shine.applying(transform), with: .color(.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            }
        }
    }
}


extension IngredientCategory {
    var iconAsset: String? {
        switch self {
        case .mushroom: "category-mushroom"
        case .soyProduct: "category-beans"
        case .staple: "category-grain"
        case .processed: "category-canned"
        default: nil
        }
    }
    var symbol: String {
        switch self {
        case .vegetable: "carrot"; case .meat: "fork.knife"; case .fish: "fish"
        case .seasoning: "takeoutbag.and.cup.and.straw"; case .eggDairy: "mug"
        default: "leaf"
        }
    }
}
struct IngredientCategoryIcon: View {
    let category: IngredientCategory
    var body: some View {
        Group {
            if let asset = category.iconAsset { Image(asset).resizable().scaledToFit() }
            else { Image(systemName: category.symbol).resizable().scaledToFit().padding(2) }
        }.frame(width: 22, height: 22).foregroundStyle(AppTheme.illustration).accessibilityHidden(true)
    }
}
struct FilterChip: View {
    let title: String
    var icon: String = "line.3.horizontal.decrease"
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(AppFont.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? AppTheme.accent.opacity(0.14) : AppTheme.background, in: Capsule())
                .foregroundStyle(selected ? AppTheme.accent : AppTheme.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct RecipeMemo: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            Image(systemName: "lightbulb").font(AppFont.body.weight(.semibold))
                .foregroundStyle(AppTheme.warning).padding(10)
                .background(AppTheme.warning.opacity(0.13), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("ひとくちメモ").font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.warning)
                Text(text).font(AppFont.subheadline).foregroundStyle(AppTheme.text)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A shadow belongs to the card silhouette, so text, photos and outlines stay flat.
struct AppSurfaceShadow {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
    static let recommendation = Self(opacity: 0.065, radius: 12, y: 4)
    static let expiry = Self(opacity: 0.045, radius: 8, y: 2)
    static let refrigerator = Self(opacity: 0.065, radius: 10, y: 3)
    static let registration = Self(opacity: 0.05, radius: 8, y: 2)
    static let selectedDay = Self(opacity: 0.08, radius: 5, y: 2)
    var color: Color { AppTheme.shadowInk.opacity(opacity) }
}

struct AppCardSurface: View {
    let cornerRadius: CGFloat
    let shadow: AppSurfaceShadow
    var fill: Color = AppTheme.surface
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill).shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FlatToolbarIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName).symbolVariant(.none).symbolRenderingMode(.monochrome)
            .font(.system(size: 22, weight: .regular)).foregroundStyle(AppTheme.accent)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder func flatToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}

struct PageHeading: ViewModifier {
    let title: String
    let icon: String
    func body(content: Content) -> some View {
        content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: icon).font(AppFont.subheadline).foregroundStyle(AppTheme.accent)
                        Text(title).font(AppFont.headline.weight(.bold)).foregroundStyle(AppTheme.text)
                    }.accessibilityElement(children: .combine)
                }
            }
    }
}

struct RecipePhoto: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let suggestion: RecipeSuggestion
    let height: CGFloat
    var thumbnail = false
    var isPrepared = false
    let identifier: String
    private var kind: String {
        [RecipeKind.main, .side, .soup].first { $0.includes(suggestion.recipe) }?.label ?? "料理"
    }
    var body: some View {
        RecipeMealImage(height: height, recipeKey: suggestion.recipe.key)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if isPrepared {
                        badge("作り置き", color: AppTheme.accent)
                    } else if thumbnail {
                        badge(suggestion.cookingTags[0].label, color: color(suggestion.cookingTags[0]), ready: suggestion.cookingTags[0] == .ready)
                    } else {
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
                        layout {
                            ForEach(suggestion.cookingTags, id: \.self) { tag in
                                badge(tag.label, color: color(tag), ready: tag == .ready)
                            }
                            badge(kind, color: AppTheme.text)
                        }
                    }
                }.padding(thumbnail ? 5 : 12)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isPrepared ? "作り置き、" + kind : (thumbnail ? [suggestion.cookingTags[0].label] : suggestion.cookingTags.map(\.label) + [kind]).joined(separator: "、"))
            .accessibilityIdentifier(identifier + "-tags")
    }
    private func color(_ tag: RecipeCookingTag) -> Color {
        switch tag { case .ready: AppTheme.success; case .shopping: AppTheme.accent; case .quantity, .review: AppTheme.warning }
    }
    private func badge(_ title: String, color: Color, ready: Bool = false) -> some View {
        HStack(spacing: 4) {
            if ready { Image(systemName: "checkmark").accessibilityHidden(true) }
            Text(title)
        }.font(ready && !thumbnail ? AppFont.caption.weight(.bold) : AppFont.caption2.weight(.bold))
            .foregroundStyle(ready ? Color.white : color)
            .padding(.horizontal, thumbnail ? 6 : 10).padding(.vertical, thumbnail ? 4 : 6)
            .background(ready ? AppTheme.readyBadge : AppTheme.surface.opacity(0.96), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}



/// A small upright outline, with no fill or decorative tilt.
struct SimpleChefHat: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.22, y: 0.62))
        path.addCurve(to: CGPoint(x: 0.24, y: 0.29), control1: CGPoint(x: 0.03, y: 0.62), control2: CGPoint(x: 0.03, y: 0.29))
        path.addCurve(to: CGPoint(x: 0.76, y: 0.29), control1: CGPoint(x: 0.24, y: 0.05), control2: CGPoint(x: 0.76, y: 0.05))
        path.addCurve(to: CGPoint(x: 0.78, y: 0.62), control1: CGPoint(x: 0.97, y: 0.29), control2: CGPoint(x: 0.97, y: 0.62))
        path.addLine(to: CGPoint(x: 0.75, y: 0.92))
        path.addLine(to: CGPoint(x: 0.25, y: 0.92))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.25, y: 0.73))
        path.addLine(to: CGPoint(x: 0.75, y: 0.73))
        return path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}
