import SwiftUI
import SafariServices

/// A rounded card on the grouped background, like Wallet and Health.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Section title in the Apple Music / Health style.
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.title2.bold())
            Spacer()
            if let trailing {
                Text(trailing).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

/// Progress bar split by who spent it, with an optional "usual" marker.
struct SplitBar: View {
    /// 0…1 of the limit used.
    let fraction: Double
    /// Who spent it, in order; empty means a single color.
    var segments: [(Color, Double)] = []
    var fill: Color = Theme.accent
    var track: Color = Color(.systemFill)
    var height: CGFloat = 6
    /// 0…1 position of the average marker.
    var marker: Double? = nil
    var markerColor: Color = .primary
    var markerLabel: String? = nil
    /// When set and over the limit, the bar keeps its colors up to the
    /// limit and shows the overspend in this color after it.
    var overflow: Color? = nil

    /// Share of the bar past the limit (0 when under).
    private var overShare: Double {
        guard overflow != nil, fraction > 1 else { return 0 }
        return (fraction - 1) / fraction
    }
    /// Where the limit sits on the bar: the end when under, earlier when over.
    private var scale: Double { 1 - overShare }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let markerLabel, let marker {
                GeometryReader { geo in
                    Text(markerLabel)
                        .font(.caption2.weight(.semibold))
                        .fixedSize()
                        .position(x: max(12, min(geo.size.width - 12, geo.size.width * min(1, marker * scale))), y: 6)
                }
                .frame(height: 12)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    HStack(spacing: 0) {
                        let usedWidth = geo.size.width * min(1, max(0, fraction)) * scale
                        if segments.isEmpty {
                            fill.frame(width: usedWidth)
                        } else {
                            let total = max(0.0001, segments.reduce(0) { $0 + $1.1 })
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                segment.0.frame(width: usedWidth * segment.1 / total)
                            }
                        }
                        if overShare > 0, let overflow {
                            // Over the limit: a gap at the limit, then the overspend.
                            Color.clear.frame(width: 2)
                            overflow
                        }
                    }
                    .frame(width: geo.size.width * min(1, max(0, fraction)), alignment: .leading)
                    .clipShape(Capsule())
                    if let marker {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(markerColor)
                            .frame(width: 2, height: height + 6)
                            .offset(x: geo.size.width * min(1, max(0, marker * scale)) - 1)
                    }
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }
}

/// Round initial for a person or Shared.
struct OwnerBadge: View {
    let owner: Owner
    let people: People
    var size: CGFloat = 28

    var body: some View {
        Text(people.initial(owner))
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(owner.ink)
            .frame(width: size, height: size)
            .background(owner.color, in: Circle())
            .accessibilityLabel(people.name(owner))
    }
}

/// The Upside app icon, drawn in SwiftUI (used in Settings and onboarding).
struct AppIconView: View {
    var size: CGFloat = 60
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Theme.iconGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Segmented "who" picker: you, your partner, shared.
struct OwnerPicker: View {
    @Binding var owner: Owner
    let people: People

    var body: some View {
        Picker("Whose account", selection: $owner) {
            ForEach(Owner.pickable) { o in
                Text(people.name(o)).tag(o)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// A category's symbol in a colored rounded square, like Settings rows.
/// An optional dot in the corner says whose account it was.
struct CategoryIcon: View {
    let categoryId: String?
    var isTransfer = false
    var isIncome = false
    var owner: Owner? = nil
    var size: CGFloat = 32

    var body: some View {
        let style = isTransfer ? ("arrow.left.arrow.right", Color.gray)
            : isIncome ? ("arrow.down", Color.green)
            : Self.style(categoryId)
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(style.1.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: style.0).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
            .overlay(alignment: .bottomTrailing) {
                if let owner, owner != .unassigned {
                    Circle().fill(owner.color)
                        .frame(width: size * 0.38, height: size * 0.38)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: size * 0.12, y: size * 0.12)
                }
            }
            .accessibilityHidden(true)
    }

    static func style(_ id: String?) -> (String, Color) {
        // Categories you add get ids like "coffee-1a2b".
        switch id.map({ String($0.split(separator: "-").first ?? "") }) {
        case "groceries": return ("cart.fill", .green)
        case "dining": return ("fork.knife", .orange)
        case "gas": return ("fuelpump.fill", .blue)
        case "commute": return ("tram.fill", .indigo)
        case "shopping": return ("bag.fill", .pink)
        case "entertainment": return ("ticket.fill", .purple)
        case "health": return ("cross.case.fill", .red)
        case "personal": return ("sparkles", .teal)
        case "kids": return ("figure.and.child.holdinghands", .yellow)
        case "pets": return ("pawprint.fill", .brown)
        case "fitness": return ("figure.run", .orange)
        case "home": return ("hammer.fill", .brown)
        case "gifts": return ("gift.fill", .red)
        case "housing": return ("house.fill", .blue)
        case "carpayment": return ("car.fill", .teal)
        case "utilities": return ("bolt.fill", .yellow)
        case "phone": return ("iphone", .gray)
        case "insurance": return ("shield.fill", .blue)
        case "subscriptions": return ("arrow.triangle.2.circlepath", .purple)
        case "taxes": return ("building.columns.fill", .gray)
        case "fees", "bankfees": return ("exclamationmark.circle.fill", .red)
        case "travel": return ("airplane", .cyan)
        case "income": return ("arrow.down", .green)
        case "childcare": return ("figure.2.and.child.holdinghands", .yellow)
        case "education": return ("graduationcap.fill", .indigo)
        case "golf": return ("figure.golf", .green)
        case "clothing": return ("tshirt.fill", .pink)
        case "giving": return ("heart.fill", .red)
        case "coffee": return ("cup.and.saucer.fill", .brown)
        case nil: return ("questionmark", .gray)
        default: return ("tag.fill", .gray)
        }
    }
}

/// Big rounded figures ("$524 left") that still grow with the Text Size
/// setting, the way Apple's own apps scale their large numbers.
private struct HeroNumber: ViewModifier {
    @ScaledMetric private var size: CGFloat
    init(size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle) }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .heavy, design: .rounded))
    }
}

extension View {
    func heroNumber(_ size: CGFloat) -> some View { modifier(HeroNumber(size: size)) }
}

/// A web page inside Upside (Safari's in-app browser), for SimpleFIN
/// Bridge: managing banks without leaving the app.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.accent)
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
