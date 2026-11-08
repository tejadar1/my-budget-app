import Foundation

/// Money set aside each month for something besides trips, like a sinking
/// fund: an emergency fund, a yearly or quarterly bill, or a big purchase.
struct Goal: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case emergency, bill, purchase
        var id: String { rawValue }
        var label: String {
            switch self {
            case .emergency: return "Emergency fund"
            case .bill: return "Yearly or quarterly bill"
            case .purchase: return "Big purchase or project"
            }
        }
        var symbol: String {
            switch self {
            case .emergency: return "lifepreserver.fill"
            case .bill: return "calendar.badge.clock"
            case .purchase: return "house.fill"
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    /// How much to have. For an emergency fund, set from months of essentials.
    var target: Cents
    /// What's saved toward it, when not following a linked account.
    var saved: Cents = 0
    /// A savings account whose balance is the goal's progress.
    var accountId: String? = nil
    /// When it's needed (a bill's due date, a purchase date). Nil = no deadline.
    var due: Date? = nil
    /// For a bill: it comes back every 3 or 12 months.
    var repeatsMonths: Int? = nil
    /// For a goal without a date: how much to put in each month.
    var monthly: Cents? = nil
}

extension BudgetStore {
    var goals: [Goal] { data.goals ?? [] }

    func goalSaved(_ goal: Goal) -> Cents {
        goal.accountId.flatMap { id in data.accounts.first { $0.id == id }?.balance } ?? goal.saved
    }

    /// What the goal needs each month: what's left spread over the months
    /// until it's due (this month included), or your own monthly amount.
    func goalMonthly(_ goal: Goal) -> Cents {
        let left = max(0, goal.target - goalSaved(goal))
        guard left > 0 else { return 0 }
        if let due = goal.due {
            let months = max(1, (calendar.dateComponents([.month], from: currentMonth, to: monthStart(due)).month ?? 0) + 1)
            return (left + months - 1) / months
        }
        return min(left, goal.monthly ?? left)
    }

    /// Everything goals take off the top this month.
    func goalsSetAside(in month: Date) -> Cents {
        guard month >= currentMonth else { return 0 }
        return goals.reduce(0) { $0 + goalMonthly($1) }
    }

    /// Essentials for a month: usual bills plus usual everyday spending.
    var monthlyEssentials: Cents {
        let month = currentMonth
        let bills = billCategoryIds.compactMap { averageSpent($0, before: month) }.reduce(0, +)
        let everyday = everydayCategories.compactMap { averageSpent($0.id, before: month) }.reduce(0, +)
        return bills + everyday
    }

    /// How many months of essentials an emergency fund covers.
    func monthsCovered(_ goal: Goal) -> Double? {
        let essentials = monthlyEssentials
        guard essentials > 0 else { return nil }
        return Double(goalSaved(goal)) / Double(essentials)
    }

    func saveGoal(_ goal: Goal) {
        var list = goals
        if let i = list.firstIndex(where: { $0.id == goal.id }) { list[i] = goal } else { list.append(goal) }
        data.goals = list
    }

    func deleteGoal(_ id: String) {
        data.goals = goals.filter { $0.id != id }
    }

    /// A bill paid: the fund starts over for the next one.
    func goalUsed(_ id: String) {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.saved = 0
        if let due = goal.due, let months = goal.repeatsMonths {
            goal.due = calendar.date(byAdding: .month, value: months, to: due)
        }
        saveGoal(goal)
    }

    /// Puts money toward a goal you track by hand.
    func addToGoal(_ id: String, _ amount: Cents) {
        guard var goal = goals.first(where: { $0.id == id }), goal.accountId == nil else { return }
        goal.saved += amount
        saveGoal(goal)
    }
}
