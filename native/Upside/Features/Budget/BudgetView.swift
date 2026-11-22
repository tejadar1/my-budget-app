import SwiftUI

/// Home, read top to bottom: how much can we spend, is anything wrong,
/// how each category is doing, goals, and everything else under More.
/// Every action sits behind a row that opens a screen explaining it.
struct BudgetView: View {
    @Environment(BudgetStore.self) private var store
    @State private var showPeople = false
    @State private var sheet: BudgetSheet?
    /// Opens after the current sheet closes (one sheet leading to another).
    @State private var nextSheet: BudgetSheet?
    @State private var path = NavigationPath()
    /// The month being looked at; nil means "this month" (follows the date).
    @State private var pickedMonth: Date?
    /// "Is Ronald Tejada one of you?" from Needs attention.
    @State private var askHousehold: String?
    @State private var askMissed: Recurring?
    /// "Ron's paycheck went down $500" from Needs attention.
    @State private var askPay: BudgetStore.PayChange?

    private var month: Date { pickedMonth ?? store.currentMonth }
    private var isCurrentMonth: Bool { month == store.currentMonth }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
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
                            MonthPlanCard(month: month, onSavings: isCurrentMonth ? { sheet = .plan } : nil)
                            if isCurrentMonth { AttentionList(open: open) }
                            SavingsRow(month: month) { sheet = .savings(month) }
                            CategoryList(month: month).id("categories")
                            GoalsSection()
                            MoreList(month: month) { sheet = .recap($0) }.id("more")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                // Pull down to sync the banks, as on Accounts.
                .refreshable { try? await BankSync.sync(store: store) }
                .onAppear {
                    // `-scrollTo more` opens partway down (used for screenshots).
                    let args = ProcessInfo.processInfo.arguments
                    guard let i = args.firstIndex(of: "-scrollTo"), i + 1 < args.count else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(args[i + 1], anchor: .top) }
                }
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
                        Button("Plan") { sheet = .plan }
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
                case .trends: TrendsView()
                case .year(let year): YearReviewView(year: year)
                case .help(let topic): HowItWorksView(focus: topic)
                }
            }
            .sheet(item: $sheet, onDismiss: {
                if let next = nextSheet { nextSheet = nil; sheet = next }
            }) { sheet in
                switch sheet {
                case .plan: PlanView()
                case .planning: PlanView(mode: .planning)
                case .limits: LimitsView()
                case .savings(let month): SavingsSheet(month: month, openPlan: isCurrentMonth ? { then(.plan) } : nil)
                case .checkIn: CheckInSheet { then(.planning) }
                case .overrun(let id): OverrunSheet(month: store.currentMonth, focus: id)
                case .bank: BankSheet()
                case .extraIncome: ExtraIncomeSheet()
                case .recap(let month): RecapView(month: month)
                case .purchase(let id): TransactionSheet(transactionId: id)
                }
            }
            .onAppear(perform: openFromLaunchArgs)
            .confirmationDialog("Plan on the new paycheck?",
                                isPresented: Binding(get: { askPay != nil }, set: { if !$0 { askPay = nil } }),
                                titleVisibility: .visible, presenting: askPay) { change in
                Button("Plan on \(Money.short(change.newMonthly)) a month") {
                    Haptics.success(); withAnimation { store.acceptPayChange(change) }
                }
                Button("Just this once") { Haptics.tap(); withAnimation { store.dismissPayChange(change) } }
            } message: { change in
                Text("This check: \(Money.short(change.latestAmount)), \(Money.short(change.perCheckDrop)) less than usual. From this month on: \(Money.short(change.oldMonthly)) → \(Money.short(change.newMonthly)) a month.")
            }
            .confirmationDialog("Is \(askHousehold ?? "") one of you?",
                                isPresented: Binding(get: { askHousehold != nil }, set: { if !$0 { askHousehold = nil } }),
                                titleVisibility: .visible) {
                if let name = askHousehold {
                    Button("Yes, one of us") { Haptics.success(); withAnimation { store.answerHousehold(name, isUs: true) } }
                    Button("No, someone we pay") { Haptics.tap(); withAnimation { store.answerHousehold(name, isUs: false) } }
                }
            } message: {
                Text("Yes: Zelles with them are transfers. No: they're spending.")
            }
            .confirmationDialog(askMissed.map { "Did \(Merchant.clean($0.name)) end?" } ?? "",
                                isPresented: Binding(get: { askMissed != nil }, set: { if !$0 { askMissed = nil } }),
                                titleVisibility: .visible, presenting: askMissed) { bill in
                Button("It ended") { Haptics.success(); withAnimation { store.answerMissedBill(bill, ended: true) } }
                Button("Not yet, still expect it") { Haptics.tap(); withAnimation { store.answerMissedBill(bill, ended: false) } }
            } message: { bill in
                Text("Ended: its \(Money.exact(bill.amount)) a month goes back to spending money. Not yet: it stays in your bills.")
            }
        }
    }

    /// Closes the open sheet, then opens `next`.
    private func then(_ next: BudgetSheet) {
        nextSheet = next
        sheet = nil
    }

    private func open(_ item: BudgetStore.Attention) {
        switch item {
        case .bank: sheet = .bank
        case .over(let id, _): sheet = .overrun(id)
        case .rebalance: sheet = .overrun(nil)
        case .onPace(let id, _): path.append(Route.category(id, store.currentMonth))
        case .checkIn: sheet = .checkIn
        case .extraIncome: sheet = .extraIncome
        case .toCheck: path.append(Route.review)
        case .household(let name): askHousehold = name
        case .billMissed(let id): askMissed = store.missedBills().first { $0.id == id }
        case .payChange(let id): askPay = store.payChanges().first { $0.sourceId == id }
        case .limitsOver: sheet = .overrun(nil)
        }
    }

    private func openFromLaunchArgs() {
        guard path.isEmpty, let open = LaunchArgs.open else { return }
        // Wait for the window to settle; a sheet asked for during launch can be dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { handleLaunch(open) }
    }

    private func handleLaunch(_ open: (kind: String, id: String)) {
        switch open.kind {
        case "category": path.append(Route.category(open.id, store.currentMonth))
        case "review": path.append(Route.review)
        case "trip": path.append(Route.trip(open.id))
        case "bills": path.append(Route.bills)
        case "cards": path.append(Route.cards)
        case "trends": path.append(Route.trends)
        case "help": path.append(Route.help(HelpTopic(rawValue: open.id)))
        case "year": path.append(Route.year(Int(open.id) ?? store.defaultReviewYear))
        case "business": path.append(Route.business)
        case "search": path.append(Route.search(open.id))
        case "limits", "recommended", "limit": sheet = .limits
        case "save", "priorities": sheet = .plan
        case "rebalance", "overrun":
            // `-tight` (screenshots): savings takes up what no limit uses, so
            // overspending has to come from somewhere.
            if ProcessInfo.processInfo.arguments.contains("-tight") {
                let month = store.currentMonth
                let allowed = store.everydayCategories.reduce(0) {
                    $0 + (store.limit($1, in: month) ?? store.averageSpent($1.id, before: month) ?? 0)
                }
                var priorities = store.data.priorities ?? Priorities()
                priorities.savings += max(0, store.monthPlan(month).toSpend - allowed)
                priorities.cardPaydown = max(priorities.cardPaydown, 20_000)
                priorities.savings -= 20_000
                store.data.priorities = priorities
            }
            sheet = .overrun(open.id.isEmpty ? nil : open.id)
        case "savings": sheet = .savings(store.currentMonth)
        case "checkin": sheet = .checkIn
        case "bank": sheet = .bank
        case "extra": sheet = .extraIncome
        case "cover":
            let id = open.id.isEmpty ? store.overruns(in: store.currentMonth).first?.id : open.id
            sheet = .overrun(id)
        case "recap": sheet = .recap(store.month(-1, from: store.currentMonth))
        case "purchase":
            // Most recent purchase in the category named by the id.
            let hit = store.data.transactions
                .filter { $0.categoryId == open.id && $0.amount < 0 }
                .max { $0.date < $1.date }
            sheet = hit.map { .purchase($0.id) }
        default: break
        }
    }
}

enum BudgetSheet: Identifiable, Hashable {
    case plan, limits, checkIn, bank, extraIncome
    /// Plan opened from the month's wrap-up: saving makes the month's plan.
    case planning
    case savings(Date)
    case overrun(String?)
    case recap(Date)
    case purchase(String)
    var id: Self { self }
}

/// A month to show in a sheet.
struct MonthRef: Identifiable, Hashable {
    let date: Date
    var id: Date { date }
}

enum Route: Hashable {
    case category(String, Date)
    case review
    case trip(String)
    case bills
    case search(String)
    case business
    case cards
    case trends
    case year(Int)
    case help(HelpTopic?)
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

/// Bar segments in owner order; empty when nothing is assigned yet so the
/// plain status color shows instead.
func segments(_ byOwner: [Owner: Cents]) -> [(Color, Double)] {
    guard Owner.pickable.contains(where: { (byOwner[$0] ?? 0) > 0 }) else { return [] }
    return Owner.allCases.compactMap { owner in
        let value = byOwner[owner] ?? 0
        return value > 0 ? (owner.color, Double(value)) : nil
    }
}

/// Green when fine, orange when nearly used up, red when over.
struct Status {
    let limit: Cents
    let left: Cents

    /// A few dollars left is nothing left: "$1 left" reads as noise, so
    /// under $10 it's simply used up.
    var usedUp: Bool { limit > 0 && left >= 0 && left < 1_000 }

    var color: Color {
        if left < 0 { return Theme.over }
        if usedUp { return .secondary }
        if limit > 0 && Double(left) < Double(limit) * 0.15 { return Theme.warning }
        return Theme.accent
    }
}

// MARK: - Rows

/// A Settings-style row: icon, title, an optional line under it, a value
/// on the right and a chevron.
struct ListRow<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueColor: Color = .secondary
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(valueColor)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// A symbol in a colored rounded square, like Settings.
struct SymbolIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Rows grouped in one rounded card, divided like a Settings list.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The divider between rows, starting after the icon.
struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 58) }
}

// MARK: - Needs attention

/// Only what needs you this month, one line each. Hidden when all is well.
struct AttentionList: View {
    @Environment(BudgetStore.self) private var store
    let open: (BudgetStore.Attention) -> Void

    var body: some View {
        let items = store.attention()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Needs attention")
                RowGroup {
                    ForEach(items) { item in
                        HStack(spacing: 0) {
                            Button { open(item) } label: { row(item) }
                                .buttonStyle(.plain)
                            if item.hideableAmount != nil {
                                Button {
                                    Haptics.tap()
                                    withAnimation { store.hideAttention(item) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3).foregroundStyle(.tertiary)
                                        .padding(.trailing, 14).padding(.leading, 2)
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hide until it changes")
                            }
                        }
                        .contextMenu {
                            if item.hideableAmount != nil {
                                Button("Hide until it changes", systemImage: "eye.slash") {
                                    withAnimation { store.hideAttention(item) }
                                }
                            }
                        }
                        if item != items.last { RowDivider() }
                    }
                }
            }
        }
    }

    /// "Ron's " or "Your " for a shared paycheck.
    private func whose(_ owner: Owner) -> String {
        let name = store.people.name(owner)
        return owner == .unassigned || owner == .shared || name.isEmpty ? "A " : name + "'s "
    }

    @ViewBuilder private func row(_ item: BudgetStore.Attention) -> some View {
        switch item {
        case .bank:
            let banks = Set(store.staleAccounts.map(\.institution))
            ListRow(title: banks.count == 1 ? "\(banks.first!) isn’t syncing" : "A bank connection needs attention",
                    subtitle: "Some purchases may be missing") {
                SymbolIcon(symbol: "exclamationmark.triangle.fill", color: .orange)
            }
        case .over(let id, let amount):
            ListRow(title: "\(store.category(id)?.name ?? "A category") is \(Money.short(amount)) over",
                    subtitle: store.overrunNote(in: store.currentMonth)) {
                CategoryIcon(categoryId: id, size: 30)
            }
        case .rebalance(let count, let amount):
            ListRow(title: "\(count) categories are \(Money.short(amount)) over",
                    subtitle: store.overrunNote(in: store.currentMonth)) {
                SymbolIcon(symbol: "exclamationmark.circle.fill", color: .red)
            }
        case .onPace(let id, let amount):
            ListRow(title: "\(store.category(id)?.name ?? "A category") is on pace to go \(Money.short(amount)) over",
                    subtitle: store.spareCovers(amount, in: store.currentMonth)
                        ? "Money not in a limit would cover it, leaving less at month end"
                        : "That would come out of savings, cards or trips") {
                CategoryIcon(categoryId: id, size: 30)
            }
        case .extraIncome(let amount):
            ListRow(title: "\(Money.short(amount)) more came in than planned",
                    subtitle: "Give it a job before it gets spent") {
                SymbolIcon(symbol: "dollarsign.circle.fill", color: Theme.accent)
            }
        case .checkIn(let decisions):
            let name = store.month(-1, from: store.currentMonth).formatted(.dateTime.month(.wide))
            ListRow(title: "Wrap up \(name)",
                    subtitle: decisions == 1 ? "1 thing to decide" : "\(decisions) things to decide") {
                SymbolIcon(symbol: "calendar.badge.checkmark", color: .indigo)
            }
        case .payChange(let id):
            if let change = store.payChanges().first(where: { $0.sourceId == id }) {
                ListRow(title: "\(whose(change.owner))paycheck went down \(Money.short(change.perCheckDrop))",
                        subtitle: change.inARow >= 2
                            ? "\(change.inARow) in a row. Plan on \(Money.short(change.newMonthly)) a month from now on?"
                            : "Plan on \(Money.short(change.newMonthly)) a month, or was it a one-off?") {
                    SymbolIcon(symbol: "arrow.down.circle.fill", color: .orange)
                }
            }
        case .billMissed(let id):
            if let bill = store.missedBills().first(where: { $0.id == id }) {
                ListRow(title: "No \(Merchant.clean(bill.name)) charge since \(bill.lastDate.formatted(.dateTime.month(.abbreviated).day()))",
                        subtitle: "Did it end? It's still counted in your bills") {
                    SymbolIcon(symbol: "calendar.badge.exclamationmark", color: .orange)
                }
            }
        case .household(let name):
            ListRow(title: "Is \(name) one of you?",
                    subtitle: "Zelles with them would be your own money moving, not spending") {
                SymbolIcon(symbol: "person.2.fill", color: .purple)
            }
        case .toCheck(let count):
            ListRow(title: count == 1 ? "1 purchase to check" : "\(count) purchases to check",
                    subtitle: "Sorted on a hunch") {
                SymbolIcon(symbol: "checklist", color: .orange)
            }
        case .limitsOver(let amount):
            ListRow(title: "Limits are \(Money.short(amount)) more than you have",
                    subtitle: store.overrunNote(in: store.currentMonth)) {
                SymbolIcon(symbol: "slider.horizontal.3", color: .red)
            }
        }
    }
}

// MARK: - Savings

/// Savings in one line and a bar; the details open in a sheet.
struct SavingsRow: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    let open: () -> Void

    var body: some View {
        let goal = store.monthPlan(month).savings
        let saved = store.savedAndInvested(in: month)
        Button(action: open) {
            RowGroup {
                VStack(spacing: 0) {
                    ListRow(title: "Savings",
                            subtitle: goal == 0 ? "Not set yet" : saved >= goal ? "Done for the month" : nil,
                            value: goal > 0 ? "\(Money.short(saved)) of \(Money.short(goal))" : Money.short(saved),
                            valueColor: saved >= goal && goal > 0 ? Theme.accent : .secondary) {
                        SymbolIcon(symbol: "banknote.fill", color: Theme.accent)
                    }
                    if goal > 0 {
                        SplitBar(fraction: Double(max(0, saved)) / Double(goal), fill: Theme.accent, height: 4)
                            .padding(.leading, 58).padding(.trailing, 16).padding(.bottom, 14).padding(.top, -4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Categories

/// Every everyday category in one list, closest to its limit first, like
/// the Health app's categories. The first six, then Show all.
struct CategoryList: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var showAll = false
    /// Remembered on this phone.
    @AppStorage("categorySort") private var sortKey = CategorySort.closest.rawValue
    /// Adjust limit, opened from a row's long-press menu.
    @State private var adjusting: CategoryRef?
    private let shown = 6

    var body: some View {
        let sort = CategorySort(rawValue: sortKey) ?? .closest
        let rows = store.categoryRows(in: month, sort: sort)
        if !rows.isEmpty {
            let spent = rows.reduce(0) { $0 + store.spent($1.id, in: month) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Categories").font(.title2.bold())
                    Spacer()
                    Text("\(Money.short(spent)) spent").font(.footnote).foregroundStyle(.secondary)
                    Menu {
                        Picker("Sort by", selection: $sortKey) {
                            ForEach(CategorySort.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 32)
                    }
                    .accessibilityLabel("Sort categories: \(sort.label)")
                }
                .padding(.top, 8)
                .sheet(item: $adjusting) { LimitAdjustSheet(categoryId: $0.id) }
                .onChange(of: sortKey) { Haptics.tap() }
                if sort != .closest {
                    Text("Sorted by \(sort.label.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                RowGroup {
                    let visible = showAll ? rows : Array(rows.prefix(shown))
                    ForEach(visible) { category in
                        NavigationLink(value: Route.category(category.id, month)) {
                            CategoryRow(category: category, month: month)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if month == store.currentMonth {
                                Button("Adjust limit", systemImage: "slider.horizontal.3") {
                                    adjusting = CategoryRef(id: category.id)
                                }
                            }
                            NavigationLink(value: Route.category(category.id, month)) {
                                Label("See purchases", systemImage: "list.bullet")
                            }
                            NavigationLink(value: Route.trends) {
                                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                            }
                        }
                        if category.id != visible.last?.id || rows.count > shown { RowDivider() }
                    }
                    if rows.count > shown {
                        Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                            Text(showAll ? "Show less" : "Show all \(rows.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Icon, name, "$524 left of $600" and a thin bar of who spent it.
struct CategoryRow: View {
    @Environment(BudgetStore.self) private var store
    let category: Category
    let month: Date

    var body: some View {
        let spent = store.spent(category.id, in: month)
        let limit = store.limit(category, in: month) ?? 0
        let left = limit - spent
        let status = Status(limit: limit, left: left)
        let skipping = limit == 0 && month == store.currentMonth && store.plan?.limits[category.id] == 0

        HStack(spacing: 12) {
            CategoryIcon(categoryId: category.id, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                // Name on its own line so it's never cut short; amount under it.
                Text(category.name).lineLimit(2)
                amount(spent: spent, limit: limit, left: left, color: status.color, skipping: skipping)
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                if limit > 0 {
                    SplitBar(fraction: Double(spent) / Double(limit),
                             segments: segments(store.spentByOwner(categoryId: category.id, in: month)),
                             fill: status.color, height: 4, overflow: Theme.over)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func amount(spent: Cents, limit: Cents, left: Cents, color: Color, skipping: Bool) -> Text {
        if skipping { return Text("Skipping this month").foregroundColor(.secondary) }
        if limit == 0 { return Text("\(Money.short(spent)) spent").foregroundColor(.secondary) }
        if left < 0 {
            return Text("\(Money.short(-left)) over").fontWeight(.semibold).foregroundColor(Theme.over)
                + Text(" \(Money.short(limit)) limit").foregroundColor(.secondary)
        }
        if Status(limit: limit, left: left).usedUp {
            return Text("Used up").fontWeight(.semibold).foregroundColor(.secondary)
                + Text(" · \(Money.short(limit)) limit").foregroundColor(.secondary)
        }
        return Text(Money.short(left)).fontWeight(.semibold).foregroundColor(color == Theme.accent ? .primary : color)
            + Text(" left of \(Money.short(limit))").foregroundColor(.secondary)
    }
}

// MARK: - More

/// Everything that isn't everyday: bills, cards, fees, business, recaps.
struct MoreList: View {
    @Environment(BudgetStore.self) private var store
    let month: Date
    let openRecap: (Date) -> Void

    var body: some View {
        let plan = store.monthPlan(month)
        let fees = store.minimizeSpent(in: month)
        let recapMonth = month == store.currentMonth ? store.month(-1, from: month) : month
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "More")
            RowGroup {
                NavigationLink(value: Route.bills) {
                    ListRow(title: "Bills", value: "\(Money.short(plan.billsPaid)) of \(Money.short(plan.bills)) paid") {
                        SymbolIcon(symbol: "doc.text.fill", color: .blue)
                    }
                }
                .buttonStyle(.plain)
                if !store.creditCards.isEmpty {
                    RowDivider()
                    NavigationLink(value: Route.cards) {
                        ListRow(title: "Credit cards", value: "\(Money.short(store.cardsOwed)) owed") {
                            SymbolIcon(symbol: "creditcard.fill", color: .indigo)
                        }
                    }
                    .buttonStyle(.plain)
                }
                RowDivider()
                NavigationLink(value: Route.category(feesCategory, month)) {
                    ListRow(title: "Fees & fines", subtitle: fees == 0 ? "None this month" : "Aim for $0",
                            value: Money.short(fees), valueColor: fees > 0 ? Theme.over : .secondary) {
                        SymbolIcon(symbol: "exclamationmark.octagon.fill", color: .red)
                    }
                }
                .buttonStyle(.plain)
                if !store.businessTransactions.isEmpty {
                    RowDivider()
                    NavigationLink(value: Route.business) {
                        ListRow(title: "Business",
                                value: store.businessOwed > 0 ? "\(Money.short(store.businessOwed)) owed to you" : "All paid back") {
                            SymbolIcon(symbol: "briefcase.fill", color: .brown)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if recapMonth >= store.firstMonth {
                    RowDivider()
                    Button { openRecap(recapMonth) } label: {
                        ListRow(title: "\(recapMonth.formatted(.dateTime.month(.wide))) recap",
                                subtitle: "How the month went and who spent what") {
                            SymbolIcon(symbol: "chart.bar.fill", color: .purple)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if store.lastFinishedMonth >= store.firstFullMonth {
                    RowDivider()
                    NavigationLink(value: Route.trends) {
                        ListRow(title: "Trends", subtitle: "Compare months and categories") {
                            SymbolIcon(symbol: "chart.line.uptrend.xyaxis", color: .teal)
                        }
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    let year = store.defaultReviewYear
                    NavigationLink(value: Route.year(year)) {
                        ListRow(title: YearReviewView.title(year, current: store.currentMonth, calendar: store.calendar),
                                subtitle: "Where the year's money went") {
                            SymbolIcon(symbol: "calendar", color: .orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The fee category with the most this month.
    private var feesCategory: String {
        store.expenseCategories.filter(\.aimsForZero)
            .max { store.spent($0.id, in: month) < store.spent($1.id, in: month) }?.id ?? "fees"
    }
}

/// A category id that can drive `.sheet(item:)`.
struct CategoryRef: Identifiable, Hashable {
    let id: String
}
