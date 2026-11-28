import Charts
import SwiftUI

/// Spent so far this month, against an even pace to `target` (dashed).
/// Drag to read a day. Draws in `tint` so it works on the green Budget card
/// as well as on a white list. An optional `compare` line is last month.
struct PaceChart: View {
    let points: [BudgetStore.DayTotal]
    let target: Cents
    let daysInMonth: Int
    var compare: [BudgetStore.DayTotal] = []
    var tint: Color = Theme.accent
    var faint: Color = .secondary
    var height: CGFloat = 90
    @State private var selected: Int?

    var body: some View {
        Chart {
            if target > 0 {
                LineMark(x: .value("Day", 1), y: .value("Pace", 0), series: .value("Line", "pace"))
                    .foregroundStyle(faint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                LineMark(x: .value("Day", daysInMonth), y: .value("Pace", Double(target) / 100), series: .value("Line", "pace"))
                    .foregroundStyle(faint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(compare) { p in
                LineMark(x: .value("Day", p.day), y: .value("Spent", Double(p.spent) / 100), series: .value("Line", "last"))
                    .foregroundStyle(faint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.day), y: .value("Spent", Double(p.spent) / 100), series: .value("Line", "this"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.day), y: .value("Spent", Double(last.spent) / 100))
                    .foregroundStyle(tint).symbolSize(40)
            }
            if let day = selected, let p = points.first(where: { $0.day == day }) {
                RuleMark(x: .value("Day", day))
                    .foregroundStyle(faint.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Text("\(day): \(Money.short(p.spent))")
                            .font(.caption.weight(.semibold)).foregroundStyle(tint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                    }
            }
        }
        .chartXScale(domain: 1...max(2, daysInMonth))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selected)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Spent so far this month")
        .accessibilityValue(points.last.map { "\(Money.short($0.spent)) by day \($0.day)" + (target > 0 ? ", of \(Money.short(target))" : "") } ?? "Nothing yet")
    }
}
