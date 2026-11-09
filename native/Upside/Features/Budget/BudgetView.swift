import SwiftUI

/// Home: one big "money left this month" answer, then your top categories.
struct BudgetView: View {
    @Environment(BudgetStore.self) private var store
    @State private var showAll = false
    @State private var showLimits = false
    @State private var showPeople = false
    @State private var showPriorities = false
    @State private var recapMonth: MonthRef?
    @State private var openPurchase: PurchaseRef?
    /// "2026-10" once you hide October's recap; next month's shows again.
    @AppStorage("hiddenRecap") private var hiddenRecap = ""
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

                    // First run: names first, then the setup steps; the plan
                    // shows once there's something to plan with.
                    if !store.people.isSetUp || showPeople {
                        PeopleCard(isEditing: $showPeople)
                    } else {
                        SetupCard()
                    }

                    if !store.data.transactions.isEmpty {
                        MonthPlanCard(month: month, onSavings: isCurrentMonth ? { showPriorities = true } : nil)

                        if isCurrentMonth {
                            SavingsCard(month: month) { showPriorities = true }
                            OverrunsCard(month: month) { showPriorities = true }
                            CheckInCard { showPriorities = true }
                        }

                        SectionTitle(text: "By category")
                        SpendingSubtotals(month: month)
                    }

                    if !store.toCheck.isEmpty {
                        NavigationLink(value: Route.review) {
                            ReviewRow(count: store.toCheck.count)
                        }
                        .buttonStyle(.plain)
                    }

                    if !store.data.transactions.isEmpty { categories }

                    BusinessRow()

                    if isCurrentMonth {
                        // Early in a month, last month's recap.
                        if store.calendar.component(.day, from: store.now()) <= 7 {
                            let last = store.month(-1, from: month)
                            let key = last.formatted(.iso8601.year().month())
                            if last >= store.firstMonth && hiddenRecap != key {
                                RecapRow(month: last, onDismiss: {
                                    withAnimation(.snappy) { hiddenRecap = key }
                                }) { recapMonth = MonthRef(date: last) }
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                        }
                    } else {
                        RecapRow(month: month) { recapMonth = MonthRef(date: month) }
                    }

                    if !store.data.transactions.isEmpty {
                        BundlesRow(month: month)

                        GoalsSection()

                        if store.data.tripsOff != true {
                            TripsSection()
                        }
                    }
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
                        Button { path.append(Route.search("")) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search purchases")
                        Button("Plan") { showPriorities = true }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .category(let id, let month): CategoryDetailView(categoryId: id, month: month)
                case .review: ReviewView()
                case .trip(let id): TripView(tripId: id)
                case .bills: BillsView()
                case .search(let query): SearchView(query: query)
                case .business: BusinessView()
                case .cards: CardsView()
                }
            }
            .sheet(isPresented: $showLimits) { LimitsView() }
            .sheet(isPresented: $showPriorities) { PlanView() }
            .sheet(item: $recapMonth) { RecapView(month: $0.date) }
            .sheet(item: $openPurchase) { TransactionSheet(transactionId: $0.id) }
            .onAppear(perform: openFromLaunchArgs)
        }
    }

    private func openFromLaunchArgs() {
        guard path.isEmpty, let open = LaunchArgs.open else { return }
        switch open.kind {
        case "category": path.append(Route.category(open.id, store.currentMonth))
        case "review": path.append(Route.review)
        case "trip": path.append(Route.trip(open.id))
        case "bills": path.append(Route.bills)
        case "cards": path.append(Route.cards)
        case "business": path.append(Route.business)
        case "search": path.append(Route.search(open.id))
        case "limits", "recommended", "limit": showLimits = true
        case "save": showPriorities = true
        case "priorities": showPriorities = true
        case "recap": recapMonth = MonthRef(date: store.month(-1, from: store.currentMonth))
        case "purchase":
            // Most recent purchase in the category named by the id.
            let hit = store.data.transactions
                .filter { $0.categoryId == open.id && $0.amount < 0 }
                .max { $0.date < $1.date }
            openPurchase = hit.map { PurchaseRef(id: $0.id) }
        default: break
        }
    }

    @ViewBuilder private var categories: some View {
        let top = store.topCategories(in: month)
        let hasTop = !top.isEmpty
        let others = store.expenseCategories.count - top.count

        if hasTop {
            let topSpent = top.reduce(0) { $0 + store.spent($1.id, in: month) }
            SectionTitle(text: "Top categories", trailing: "\(Money.short(topSpent)) spent")
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
                    let groupSpent = group.categories.reduce(0) { $0 + store.spent($1.id, in: month) }
                    SectionTitle(text: group.name, trailing: "\(Money.short(groupSpent)) spent")
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
    case bills
    case search(String)
    case business
    case cards
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
        HStack(spacing: 0) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button { move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
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
                    Text(spent > 0 ? "keep this at $0" : "none this month")
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
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 purchase to check" : "\(count) purchases to check")
                    .font(.headline)
                Text("Sorted on a hunch. Tap ✓ or fix it once.")
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

/// A month to show in a sheet.
struct MonthRef: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
}

/// Sheet identity for opening a purchase from a launch argument.
struct PurchaseRef: Identifiable { let id: String }

/// Categories past their limit, each with a way to cover it from another
/// category's room (or unassigned money) for this month, so the month
/// still adds up instead of quietly eating into savings.
struct OverrunsCard: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    let openPlan: () -> Void

    var body: some View {
        let overruns = store.overruns(in: month)
        if !overruns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("OVER THIS MONTH").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                ForEach(overruns) { overrun in
                    row(overrun)
                    if overrun.id != overruns.last?.id { Divider() }
                }
                Text("Covering moves room from another category for this month only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func row(_ overrun: BudgetStore.Overrun) -> some View {
        // Round up to whole dollars so the category ends at $0 left, not -$0.40.
        let amount = (overrun.over + 99) / 100 * 100
        let sources = store.coverSources(for: overrun.id, in: month).filter { $0.room >= amount }
        return HStack {
            CategoryIcon(categoryId: overrun.category.id, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(overrun.category.name)
                Text("\(Money.short(amount)) over").font(.footnote.weight(.semibold)).foregroundStyle(Theme.over)
            }
            Spacer()
            Menu {
                if sources.isEmpty {
                    Button("Change the plan…", action: openPlan)
                } else {
                    Section("Cover \(Money.short(amount)) from") {
                        ForEach(sources) { source in
                            Button("\(source.name) (\(Money.short(source.room)) left)") {
                                withAnimation { store.cover(overrun.id, amount: amount, from: source.id, in: month) }
                            }
                        }
                    }
                }
            } label: {
                Text("Cover").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Early in a month: last month's plan versus what happened. Shortfalls
/// (savings not moved, cards not paid) and unspent money each get a choice,
/// so nothing quietly disappears.
struct CheckInCard: View {
    @Environment(BudgetStore.self) private var store
    let openPlan: () -> Void

    var body: some View {
        if let check = store.monthCheckIn() {
            let name = check.month.formatted(.dateTime.month(.wide))
            VStack(alignment: .leading, spacing: 12) {
                Text("\(name.uppercased()) CHECK-IN").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                if check.savingsShort > 0 {
                    shortRow("Savings", check.savingsShort, .savings, check.month)
                }
                if check.cardsShort > 0 {
                    if check.savingsShort > 0 { Divider() }
                    shortRow("Card paydown", check.cardsShort, .cards, check.month)
                }
                if check.unspent > 0 {
                    if check.savingsShort > 0 || check.cardsShort > 0 { Divider() }
                    unspentRow(check.unspent, check.month)
                }
                Button("Plan was too much? Lower it in Plan", action: openPlan)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .card()
        }
    }

    private func shortRow(_ title: String, _ amount: Cents, _ item: BudgetStore.CheckInItem, _ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("\(Money.short(amount)) short").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.over)
            }
            Text(item == .savings ? "Planned but not moved to savings. It’s still in checking."
                                  : "Planned but not paid toward cards. It’s still in checking.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                choice("Catch up this month") { store.catchUp(item, amount, for: month) }
                choice("Let it go") { store.letGo(item, for: month) }
            }
        }
    }

    private func unspentRow(_ amount: Cents, _ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Not spent").font(.headline)
                Spacer()
                Text(Money.short(amount)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            Text("Give it a job so it doesn’t just sit in checking.").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                choice("Savings") { store.useUnspent(amount, for: month, as: .savings) }
                if store.cardsOwed > 0 {
                    choice("Cards") { store.useUnspent(amount, for: month, as: .cards) }
                }
                choice("Keep") { store.useUnspent(amount, for: month, as: .keep) }
            }
        }
    }

    private func choice(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() } } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
    }
}
