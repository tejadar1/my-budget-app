import SwiftUI

/// Wallet-style accounts: each account is a colored card with its owner.
struct AccountsView: View {
    @Environment(BudgetStore.self) private var store
    @State private var selected: Account?
    @State private var showConnect = false
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !store.data.accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
                            Text(Money.short(store.netWorth))
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(store.netWorth < 0 ? Theme.over : Theme.accent)
                            if let last = store.data.lastBankSync {
                                Text("Updated \(last.formatted(.relative(presentation: .named)))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !store.data.bankConnected {
                        connectCard
                    }

                    if store.people.isSetUp && !store.unclaimedAccounts.isEmpty {
                        WhoseCard()
                    }

                    CardsCheck()

                    VStack(spacing: 12) {
                        ForEach(store.data.accounts) { account in
                            Button { selected = account } label: {
                                WalletCard(account: account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await sync() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Accounts")
            .toolbar {
                if store.data.bankConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { Task { await sync() } } label: {
                                Label("Sync now", systemImage: "arrow.clockwise")
                            }
                            Button { showConnect = true } label: {
                                Label("Link another bank", systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "ellipsis.circle")
                                .symbolEffect(.pulse, isActive: isSyncing)
                        }
                    }
                }
            }
            .sheet(item: $selected) { account in AccountSheet(accountId: account.id) }
            .sheet(isPresented: $showConnect) { ConnectBanksView() }
            .onAppear {
                if let open = LaunchArgs.open, open.kind == "account", selected == nil {
                    selected = store.account(open.id)
                }
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your banks").font(.title3.bold())
            Text("Link your banks and cards once at SimpleFIN; Upside adds every account and keeps them up to date.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                showConnect = true
            } label: {
                Text("Connect banks").bold().frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
        }
        .card(padding: 18)
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        try? await BankSync.sync(store: store)
    }
}

struct WalletCard: View {
    @Environment(BudgetStore.self) private var store
    let account: Account

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.headline).lineLimit(1)
                    Text([account.institution, account.isOnBudget ? nil : "Off budget"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                HStack(spacing: 6) {
                    OwnerBadge(owner: account.owner, people: store.people, size: 20)
                    Text(store.people.name(account.owner)).font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .background(.black.opacity(0.35), in: Capsule())
            }
            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.balance < 0 ? "Owed" : "Balance").font(.caption).opacity(0.85)
                Text(Money.exact(abs(account.balance)))
                    .font(.system(.title, design: .rounded).weight(.heavy))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(Theme.cardGradient(for: account.institution + account.kind.rawValue),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

/// Accounts nobody has claimed yet.
struct WhoseCard: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Whose accounts are these?").font(.headline)
                Text("This decides how spending shows up in who spent what.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.unclaimedAccounts) { account in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(account.institution) · \(account.name)").font(.subheadline.weight(.semibold))
                    OwnerPicker(owner: Binding(
                        get: { account.owner },
                        set: { store.setOwner(account.id, $0) }), people: store.people)
                }
            }
        }
        .card()
    }
}

struct AccountSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let accountId: String

    var body: some View {
        NavigationStack {
            if let account = store.account(accountId) {
                List {
                    Section {
                        WalletCard(account: account)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section("Whose account") {
                        OwnerPicker(owner: Binding(
                            get: { account.owner },
                            set: { store.setOwner(account.id, $0) }), people: store.people)
                    }
                    Section {
                        Toggle("Count in monthly budget", isOn: Binding(
                            get: { account.isOnBudget },
                            set: { newValue in
                                if let i = store.data.accounts.firstIndex(where: { $0.id == account.id }) {
                                    store.data.accounts[i].isOnBudget = newValue
                                }
                            }))
                    } footer: {
                        Text("Turn off for mortgages, 401(k)s and other accounts that aren’t everyday spending.")
                    }
                    Section("Recent") {
                        ForEach(store.data.transactions.filter { $0.accountId == account.id }.prefix(30)) { t in
                            TransactionRow(transaction: t)
                        }
                    }
                }
                .navigationTitle(account.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
    }
}
