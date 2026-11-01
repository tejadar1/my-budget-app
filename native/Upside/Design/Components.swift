import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let markerLabel, let marker {
                GeometryReader { geo in
                    Text(markerLabel)
                        .font(.caption2.weight(.semibold))
                        .fixedSize()
                        .position(x: max(12, min(geo.size.width - 12, geo.size.width * marker)), y: 6)
                }
                .frame(height: 12)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    HStack(spacing: 0) {
                        if segments.isEmpty {
                            fill
                        } else {
                            let total = max(0.0001, segments.reduce(0) { $0 + $1.1 })
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                segment.0.frame(width: geo.size.width * min(1, fraction) * segment.1 / total)
                            }
                        }
                    }
                    .frame(width: geo.size.width * min(1, max(0, fraction)), alignment: .leading)
                    .clipShape(Capsule())
                    if let marker {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(markerColor)
                            .frame(width: 2, height: height + 6)
                            .offset(x: geo.size.width * min(1, max(0, marker)) - 1)
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
