import Charts
import SwiftUI

/// Months side by side: spending and income over the last year, what
/// changed last month, and every category's last six months.
struct TrendsView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let totals = store.monthTotals(endingAt: store.currentMonth)
        let finished = totals.filter { $0.month < store.currentMonth }
        let last = store.lastFinishedMonth
        let changes = last >= store.firstFullMonth ? store.categoryChanges(in: last) : []
        let trends = store.categoryTrends(endingAt: last)

        List {
            if totals.count >= 2 {
                Section {
                    SpendingChart(totals: totals, current: store.currentMonth)
                        .padding(.vertical, 6)
                } header: {
                    Text("Spent each month")
                } footer: {
                    Text([BudgetStore.spendingNote(finished),
                          "Bills included, trips not. This month is so far."].compactMap { $0 }.joined(separator: " "))
                }
            }

            Section {
                NavigationLink(value: Route.year(store.defaultReviewYear)) {
                    Label(YearReviewView.title(store.defaultReviewYear, current: store.currentMonth,
                                               calendar: store.calendar),
                          systemImage: "calendar")
                }
            }

            if !changes.isEmpty {
                Section {
                    ForEach(changes.prefix(6)) { change in
                        NavigationLink(value: Route.category(change.category.id, last)) {
                            HStack(spacing: 12) {
                                CategoryIcon(categoryId: change.category.id, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.category.name)
                                    Text(change.usual > 0
                                         ? "\(Money.short(change.spent)) · usually \(Money.short(change.usual))"
                                         : "\(Money.short(change.spent)) · new")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(change.diff > 0 ? "+\(Money.short(change.diff))" : "−\(Money.short(-change.diff))")
                                    .fontWeight(.semibold).monospacedDigit()
                                    .foregroundStyle(change.diff > 0 ? Theme.warning : Theme.accent)
                            }
                        }
                    }
                } header: {
                    Text("What changed in \(last.formatted(.dateTime.month(.wide)))")
                } footer: {
                    Text("Compared with the three months before.")
                }
            }

            if !trends.isEmpty {
                Section {
                    ForEach(trends) { trend in
                        NavigationLink(value: Route.category(trend.category.id, last)) {
                            CategoryTrendRow(trend: trend)
                        }
                    }
                } header: {
                    Text("Every category, last \(trends.first?.points.count ?? 6) months")
                } footer: {
                    Text("Average per month. Tap one for its purchases.")
                }
            }
        }
        .overlay {
            if totals.count < 2 {
                ContentUnavailableView("Not enough history yet", systemImage: "chart.bar",
                                       description: Text("Trends show once there are two months to compare."))
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Bars for spending, a line for income; this month lighter (it's not over).
private struct SpendingChart: View {
    let totals: [MonthTotal]
    let current: Date

    var body: some View {
        Chart {
            ForEach(totals) { point in
                BarMark(x: .value("Month", point.month, unit: .month),
                        y: .value("Spent", Double(point.spent) / 100))
                    .foregroundStyle(point.month == current ? Theme.accent.opacity(0.35) : Theme.accent)
                    .cornerRadius(4)
            }
            ForEach(totals.filter { $0.income > 0 && $0.month < current }) { point in
                LineMark(x: .value("Month", point.month, unit: .month),
                         y: .value("Income", Double(point.income) / 100))
                    .foregroundStyle(by: .value("Series", "Income"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .symbol(.circle)
                    .symbolSize(24)
            }
        }
        .chartForegroundStyleScale(["Income": Color.secondary])
        .chartLegend(position: .top, alignment: .trailing)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let dollars = value.as(Double.self) { Text(Money.short(Cents(dollars * 100))) }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Spending for the last \(totals.count) months")
        .accessibilityValue(totals.map { "\($0.month.formatted(.dateTime.month(.wide))) \(Money.short($0.spent))" }
            .joined(separator: ", "))
    }
}

/// A category with its average and a small bar per month.
private struct CategoryTrendRow: View {
    let trend: CategoryTrend

    var body: some View {
        let peak = max(1, trend.points.map(\.spent).max() ?? 1)
        HStack(spacing: 12) {
            CategoryIcon(categoryId: trend.category.id, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(trend.category.name).lineLimit(1)
                Text(trend.note ?? "\(Money.short(trend.average)) a month")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(trend.points) { point in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(point.id == trend.points.last?.id ? Theme.accent : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: max(2, 24 * CGFloat(point.spent) / CGFloat(peak)))
                }
            }
            .frame(height: 24, alignment: .bottom)
            .accessibilityHidden(true)
            Text(Money.short(trend.average))
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Year in review

/// The year at a glance: money in and out, where it went, the best and
/// worst months, who spent, the biggest purchases.
struct YearReviewView: View {
    @Environment(BudgetStore.self) private var store
    @State var year: Int

    /// "2025 in review" once the year is over, "2026 so far" before.
    static func title(_ year: Int, current: Date, calendar: Calendar) -> String {
        year < calendar.component(.year, from: current) ? "\(String(year)) in review" : "\(String(year)) so far"
    }

    var body: some View {
        let review = store.yearReview(year)
        let years = store.reviewYears
        List {
            if years.count > 1 {
                Section {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Money.short(review.spent)).heroNumber(40)
                    Text("spent \(coverage(review))").foregroundStyle(.secondary)
                    if let average = review.monthlyAverage {
                        Text("A typical month: \(Money.short(average)), not counting trips")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                if let first = review.months.first, store.calendar.component(.month, from: first) > 1 {
                    Text("Your bank history starts in \(first.formatted(.dateTime.month(.wide))), so the year starts there.")
                }
            }

            if review.income > 0 {
                Section("Money in and out") {
                    LabeledContent("Income", value: Money.short(review.income))
                    LabeledContent("Spent, including bills and trips", value: Money.short(review.spent))
                    if review.trips > 0 {
                        LabeledContent("Trips", value: Money.short(review.trips))
                    }
                    LabeledContent("Saved & invested", value: Money.short(review.saved))
                    LabeledContent(review.leftOver >= 0 ? "Left over" : "Short") {
                        Text(Money.short(review.leftOver))
                            .fontWeight(.semibold)
                            .foregroundStyle(review.leftOver >= 0 ? Theme.accent : Theme.over)
                    }
                }
            }

            if !review.categories.isEmpty {
                Section("Where it went") {
                    let total = max(1, review.categories.reduce(0) { $0 + $1.spent })
                    ForEach(review.categories.prefix(8)) { item in
                        NavigationLink(value: Route.category(item.category.id, review.months.last ?? store.currentMonth)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    CategoryIcon(categoryId: item.category.id, size: 26)
                                    Text(item.category.name)
                                    Spacer()
                                    Text(Money.short(item.spent)).monospacedDigit()
                                    Text("\(Int((Double(item.spent) / Double(total) * 100).rounded()))%")
                                        .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                                        .frame(minWidth: 34, alignment: .trailing)
                                }
                                ProgressView(value: Double(item.spent), total: Double(total))
                                    .tint(Theme.accent)
                            }
                        }
                    }
                }
            }

            if review.highest != nil || review.monthsWithPlan > 0 {
                Section {
                    if let high = review.highest {
                        LabeledContent("Most spent", value: "\(high.month.formatted(.dateTime.month(.wide))) · \(Money.short(high.spent))")
                    }
                    if let low = review.lowest {
                        LabeledContent("Least spent", value: "\(low.month.formatted(.dateTime.month(.wide))) · \(Money.short(low.spent))")
                    }
                    if review.monthsWithPlan > 0 {
                        LabeledContent("Within the plan",
                                       value: "\(review.monthsOnPlan) of \(review.monthsWithPlan) month\(review.monthsWithPlan == 1 ? "" : "s")")
                    }
                } header: {
                    Text("Months")
                } footer: {
                    Text("Finished months, not counting trips.")
                }
            }

            let owners = Owner.allCases.filter { (review.byOwner[$0] ?? 0) > 0 }
            if store.people.isSetUp && !owners.isEmpty {
                Section("Who spent") {
                    ForEach(owners) { owner in
                        HStack(spacing: 12) {
                            OwnerBadge(owner: owner, people: store.people, size: 28)
                            Text(store.people.name(owner))
                            Spacer()
                            Text(Money.short(review.byOwner[owner] ?? 0)).fontWeight(.semibold).monospacedDigit()
                        }
                    }
                }
            }

            if !review.biggest.isEmpty {
                Section("Biggest purchases") {
                    ForEach(review.biggest) { TransactionRow(transaction: $0) }
                }
            }

            Section {
                LabeledContent("Fees & fines") {
                    Text(Money.short(review.fees)).foregroundStyle(review.fees > 0 ? Theme.over : Theme.accent)
                }
            } footer: {
                Text(review.fees == 0 ? "No fees or interest all year." : "Money that bought nothing. Aim for $0.")
            }
        }
        .overlay {
            if review.months.isEmpty {
                ContentUnavailableView("No history for \(String(year))", systemImage: "calendar",
                                       description: Text("Your bank history doesn't reach this year."))
            }
        }
        .navigationTitle(Self.title(year, current: store.currentMonth, calendar: store.calendar))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "in 2026" for a full year; "June–November" otherwise.
    private func coverage(_ review: YearReview) -> String {
        guard let first = review.months.first, let last = review.months.last else { return "" }
        if review.months.count == 12 { return "in \(String(review.year))" }
        let f = first.formatted(.dateTime.month(.wide))
        let l = last.formatted(.dateTime.month(.wide))
        let soFar = last == store.currentMonth ? " (so far)" : ""
        return first == last ? "in \(f)\(soFar)" : "\(f)–\(l)\(soFar)"
    }
}
