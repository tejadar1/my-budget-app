import SwiftUI

/// What Upside learned about the people you pay through Zelle, Venmo and
/// Cash App, and who's one of you. Everything here came from your sorting.
struct PeopleYouPayView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let rules = store.personRules
        let paid = rules.filter { !$0.incoming }
        let back = rules.filter(\.incoming)
        let household = (store.data.householdPayees ?? [:]).sorted { $0.key < $1.key }

        List {
            if !household.isEmpty {
                Section {
                    ForEach(household, id: \.key) { name, isUs in
                        Toggle(isOn: Binding(get: { isUs }, set: { on in
                            Haptics.tap()
                            withAnimation { store.answerHousehold(title(name), isUs: on) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(name))
                                Text(isUs ? "One of you: a transfer" : "Someone you pay").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } header: {
                    Text("One of you?")
                } footer: {
                    Text("On: Zelles with them are your own money moving, not spending.")
                }
            }

            if !paid.isEmpty {
                Section {
                    ForEach(paid) { rule in row(rule) }
                } header: {
                    Text("People you pay")
                } footer: {
                    Text("Changing one moves their past payments too. Forget, and their next payment goes to Check these.")
                }
            }

            if !back.isEmpty {
                Section("People who pay you back") {
                    ForEach(back) { rule in row(rule) }
                }
            }
        }
        .overlay {
            if rules.isEmpty && household.isEmpty {
                ContentUnavailableView("No one yet", systemImage: "person.2",
                                       description: Text("Sort a Zelle, Venmo or Cash App payment in Check these and the person shows up here."))
            }
        }
        .navigationTitle("People you pay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ rule: BudgetStore.PersonRule) -> some View {
        Picker(selection: Binding(get: { rule.categoryId }, set: { id in
            Haptics.tap()
            withAnimation { store.setPersonRule(rule.key, to: id) }
        })) {
            ForEach(store.groupedCategories) { group in
                Section(group.name) {
                    ForEach(group.categories) { Text($0.name).tag($0.id) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                Text(service(rule.service) + (rule.incoming ? " · paying you" : "")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("Forget", role: .destructive) { withAnimation { store.forgetPersonRule(rule.key) } }
        }
    }

    private func service(_ s: String) -> String {
        ["zelle": "Zelle", "venmo": "Venmo", "cash app": "Cash App", "apple cash": "Apple Cash"][s] ?? s
    }

    private func title(_ name: String) -> String {
        name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
