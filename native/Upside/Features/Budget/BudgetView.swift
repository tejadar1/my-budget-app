import SwiftUI

/// Home: one big "money left this month" answer, then your top categories.
struct BudgetView: View {
    @Environment(BudgetStore.self) private var store
    @State private var showAll = false
    @State private var showLimits = false
    @State private var showPeople = false
    @State private var showSave = false
    @State private var path = NavigationPath()
    /// The month being looked at; nil means "this month" (follows the date).
    @State private var pickedMonth: Date?

    private var month: Date { pickedMonth ?? store.currentMonth }
    private var isCurrentMonth: Bool { month == store.currentMonth }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MonthSwitcher(month: month,
                                  canGoBack: month > store.firstMonth,
                                  canGoForward: !isCurrentMonth,
                                  isCurrent: isCurrentMonth) { offset in
                        withAnimation(.snappy) {
                            let next = store.month(offset, from: month)
                            pickedMonth = next >= store.currentMonth ? nil : next
                        }
                    }
                    .padding(.top, -8)

                    SetupCard()

                    if !store.people.isSetUp || showPeople {
                        PeopleCard(isEditing: $showPeople)
                    }

                    SummaryCard(month: month)

                    if isCurrentMonth {
                        CardWarningRow()
                        SavingsRow { showSave = true }
                    }

                    FeesRow(month: month)

                    if !store.uncategorized.isEmpty {
                        NavigationLink(value: Route.review) {
                            ReviewRow(count: store.uncategorized.count)
                        }
                        .buttonStyle(.plain)
                    }

                    categories

                    TripsSection()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if store.people.isSetUp {
                            Button { showPeople = true } label: {
                                HStack(spacing: -8) {
                                    OwnerBadge(owner: .p1, people: store.people, size: 30)
                                    if !store.people.p2.isEmpty {
                                        OwnerBadge(owner: .p2, people: store.people, size: 30)
                                    }
                                }
                            }
                            .accessibilityLabel("Edit names")
                        }
                        Button("Limits") { showLimits = true }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .category(let id, let month): CategoryDetailView(categoryId: id, month: month)
                case .review: ReviewView()
                case .trip(let id): TripView(tripId: id)
                }
            }
            .sheet(isPresented: $showLimits) { LimitsView() }
            .sheet(isPresented: $showSave) { SavingsPlanView() }
            .onAppear(perform: openFromLaunchArgs)
        }
    }

    private func openFromLaunchArgs() {
        guard path.isEmpty, let open = LaunchArgs.open else { return }
        switch open.kind {
        case "category": path.append(Route.category(open.id, store.currentMonth))
        case "review": path.append(Route.review)
        case "trip": path.append(Route.trip(open.id))
        case "limits": showLimits = true
        case "save": showSave = true
        default: break
        }
    }

    @ViewBuilder private var categories: some View {
        let top = store.topCategories(in: month)
        let hasTop = !top.isEmpty
        let others = store.expenseCategories.count - top.count

        if hasTop {
            SectionTitle(text: "Top categories")
            CategoryGrid(categories: top, month: month)
        }

        if hasTop && others > 0 {
            Button {
                withAnimation(.snappy) { showAll.toggle() }
            } label: {
                HStack {
                    Text("All categories").foregroundStyle(.primary)
                    Spacer()
                    Text(showAll ? "Hide" : "\(others) more").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAll ? 90 : 0))
                }
                .card()
            }
            .buttonStyle(.plain)
        }

        if showAll || !hasTop {
            ForEach(store.groupedCategories) { group in
                if group.name != "Trips" {
                    SectionTitle(text: group.name)
                    CategoryGrid(categories: group.categories, month: month)
                }
            }
        }
    }
}

enum Route: Hashable {
    case category(String, Date)
    case review
    case trip(String)
}

// MARK: - Month switcher

/// ‹ OCTOBER 2026 › — go back through past months.
struct MonthSwitcher: View {
    let month: Date
    let canGoBack: Bool
    let canGoForward: Bool
    let isCurrent: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button { move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")

            Spacer()

            if !isCurrent {
                Button("This month") { move(12 * 100) }
                    .font(.footnote.weight(.semibold))
            }
        }
        .font(.footnote.weight(.bold))
        .padding(.leading, -8)
    }
}

// MARK: - Summary

struct SummaryCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date

    var body: some View {
        let limit = store.totalLimit(in: month)
        let spent = store.totalSpent(in: month)
        let left = limit - spent
        let hasLimits = limit > 0
        let isOver = hasLimits && left < 0
        let isPast = month < store.currentMonth
        let average = store.averageTotal(before: month)
        let byOwner = store.spentByOwner(in: month)

        VStack(alignment: .leading, spacing: 14) {
            Text(isPast ? month.formatted(.dateTime.month(.wide)).uppercased() : "THIS MONTH")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 4) {
                Text(!hasLimits ? "\(Money.short(spent)) spent"
                     : isOver ? "\(Money.short(left)) over"
                     : isPast ? "\(Money.short(left)) under" : "\(Money.short(left)) left")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(!hasLimits ? "No monthly limits yet"
                     : isPast ? "spent \(Money.short(spent)) of \(Money.short(limit))"
                     : "of \(Money.short(limit)) · \(daysLeftText)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                if let average {
                    Text("Your usual month: \(Money.short(average))")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.86))
                }
            }

            if hasLimits {
                SplitBar(
                    fraction: Double(spent) / Double(max(1, limit)),
                    segments: isOver ? [] : segments(byOwner),
                    fill: isOver ? Theme.over : .white,
                    track: .black.opacity(0.3),
                    height: 10,
                    marker: average.map { Double($0) / Double(max(1, limit)) },
                    markerColor: .white,
                    markerLabel: "usual")
            } else {
                Button {
                    withAnimation { store.setLimitsFromAverages() }
                } label: {
                    Text("Use my averages as limits")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color(hex: 0x14532D))
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if store.people.isSetUp && !byOwner.isEmpty {
                HStack {
                    ForEach(Owner.allCases.filter { (byOwner[$0] ?? 0) > 0 }) { owner in
                        HStack(spacing: 6) {
                            Circle().fill(owner.color).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                            Text(store.people.name(owner))
                            Text(Money.short(byOwner[owner] ?? 0)).bold()
                        }
                        .font(.footnote)
                        if owner != Owner.allCases.last { Spacer(minLength: 4) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var daysLeftText: String {
        switch store.daysLeftInMonth {
        case 0: return "last day of the month"
        case 1: return "1 day to go"
        case let n: return "\(n) days to go"
        }
    }
}

/// Bar segments in owner order; empty when nothing is assigned yet so the
/// plain status color shows instead.
func segments(_ byOwner: [Owner: Cents]) -> [(Color, Double)] {
    guard Owner.pickable.contains(where: { (byOwner[$0] ?? 0) > 0 }) else { return [] }
    return Owner.allCases.compactMap { owner in
        let value = byOwner[owner] ?? 0
        return value > 0 ? (owner.color, Double(value)) : nil
    }
}

// MARK: - Category cards

struct CategoryGrid: View {
    let categories: [Category]
    let month: Date

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(categories) { category in
                NavigationLink(value: Route.category(category.id, month)) {
                    CategoryCard(category: category, month: month)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CategoryCard: View {
    @Environment(BudgetStore.self) private var store
    let category: Category
    let month: Date

    var body: some View {
        let spent = store.spent(category.id, in: month)
        let average = store.averageSpent(category.id, before: month)
        let limit = store.limit(category, in: month) ?? 0
        let left = limit - spent
        let status = Status(limit: limit, left: left)
        let isPlanned = store.plan?.limits[category.id] != nil && month == store.currentMonth

        VStack(alignment: .leading, spacing: 10) {
            Text(category.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                if category.aimsForZero {
                    Text(Money.short(spent))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(spent > 0 ? Theme.over : Theme.accent)
                    Text(spent > 0 ? "aim for $0" : "none this month")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(limit == 0 && !isPlanned ? Money.short(spent)
                         : left < 0 ? "\(Money.short(left)) over" : Money.short(left))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(limit == 0 && !isPlanned ? Color.primary : status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isPlanned && limit == 0 ? "skipping this month"
                         : limit == 0 ? "spent · no limit"
                         : left < 0 ? "limit \(Money.short(limit))"
                         : isPlanned ? "left of \(Money.short(limit)) · saving"
                         : "left of \(Money.short(limit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let average {
                        Text("usual \(Money.short(average))/mo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if limit > 0 {
                SplitBar(
                    fraction: Double(spent) / Double(limit),
                    segments: segments(store.spentByOwner(categoryId: category.id, in: month)),
                    fill: status.color,
                    marker: average.map { Double($0) / Double(limit) })
            }
        }
        .card()
        .contentShape(Rectangle())
    }
}

/// Green when fine, orange when nearly used up, red when over.
struct Status {
    let limit: Cents
    let left: Cents

    var color: Color {
        if left < 0 { return Theme.over }
        if limit > 0 && Double(left) < Double(limit) * 0.15 { return Theme.warning }
        return Theme.accent
    }
}

// MARK: - Review row

struct ReviewRow: View {
    let count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 purchase to sort" : "\(count) purchases to sort")
                    .font(.headline)
                Text("Pick a category once; Upside remembers the store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
    }
}
