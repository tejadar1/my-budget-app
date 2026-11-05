import SwiftUI

/// Wallet-style accounts: each account is a colored card with its owner.
struct AccountsView: View {
    @Environment(BudgetStore.self) private var store
    @State private var selected: Account?
    @State private var showConnect = false
    @State private var isSyncing = false
    @State private var showReorder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !store.data.accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
                            Text(Money.short(store.netWorth))
                                .heroNumber(40)
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

                    if store.data.bankConnected {
                        BankHealthCard()
                    }

                    if store.people.isSetUp && !store.unclaimedAccounts.isEmpty {
                        WhoseCard()
                    }

                    VStack(spacing: 12) {
                        ForEach(store.activeAccounts) { account in
                            Button { selected = account } label: {
                                WalletCard(account: account)
                            }
                            .buttonStyle(.plain)
                            // Long-press to hide without opening the account.
                            .contextMenu {
                                Button { withAnimation { store.setHidden(account.id, true) } } label: {
                                    Label("Hide account", systemImage: "eye.slash")
                                }
                            }
                        }
                    }

                    if !store.emptyAccounts.isEmpty {
                        AccountGroupSection(title: "Empty accounts", icon: "tray",
                                            note: "$0 and no activity in 90 days. They come back when they're used.",
                                            accounts: store.emptyAccounts, buttonTitle: "Hide") { store.setHidden($0, true) }
                    }
                    if !store.hiddenAccounts.isEmpty {
                        AccountGroupSection(title: "Hidden accounts", icon: "eye.slash", note: nil,
                                            accounts: store.hiddenAccounts, buttonTitle: "Show") { store.setHidden($0, false) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await sync() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Accounts")
            .toolbar {
                if !store.data.accounts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if store.data.bankConnected {
                                Button { Task { await sync() } } label: {
                                    Label("Sync now", systemImage: "arrow.clockwise")
                                }
                                Button { showConnect = true } label: {
                                    Label("Link another bank", systemImage: "plus")
                                }
                            }
                            Button { showReorder = true } label: {
                                Label("Reorder accounts", systemImage: "arrow.up.arrow.down")
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
            .sheet(isPresented: $showReorder) { ReorderAccountsView() }
            .onAppear {
                if let open = LaunchArgs.open, open.kind == "account", selected == nil {
                    selected = store.account(open.id)
                }
                if LaunchArgs.open?.kind == "reorder" { showReorder = true }
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
                    Text(account.fullName).font(.subheadline.weight(.semibold))
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
                    if let updated = account.bankUpdated {
                        Section {
                            LabeledContent("Bank last updated",
                                           value: updated.formatted(.relative(presentation: .named)))
                        } footer: {
                            if store.isStale(account) {
                                Text("\(account.institution) hasn’t sent anything new in a while. Check the connection at SimpleFIN Bridge.")
                                    .foregroundStyle(Theme.over)
                            }
                        }
                    }
                    Section {
                        Picker("Type", selection: Binding(
                            get: { account.kind },
                            set: { kind in
                                if let i = store.data.accounts.firstIndex(where: { $0.id == account.id }) {
                                    store.data.accounts[i].kind = kind
                                    BankSync.markTransfers(&store.data)
                                }
                            })) {
                            ForEach(AccountKind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    } footer: {
                        if account.kind == .credit {
                            Text("Payments to cards aren’t spending.")
                        }
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
                        Text("Off for mortgages, 401(k)s and other non-everyday accounts.")
                    }
                    Section {
                        // Hiding can be undone, so it isn't styled as destructive.
                        Button(account.isHidden ? "Show account" : "Hide account") {
                            store.setHidden(account.id, !account.isHidden)
                            if !account.isHidden { dismiss() }
                        }
                    } footer: {
                        Text("Leaves Accounts, net worth and your budget. Show it again at the bottom of Accounts.")
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

/// Drag accounts into the order you want; it's kept across syncs (new
/// accounts are added at the end).
struct ReorderAccountsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.accounts) { account in
                    HStack(spacing: 12) {
                        OwnerBadge(owner: account.owner, people: store.people, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.isHidden ? "\(account.institution) · Hidden" : account.institution)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { store.data.accounts.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Bottom of Accounts: a collapsible group of accounts with one action each.
private struct AccountGroupSection: View {
    let title: String
    let icon: String
    let note: String?
    let accounts: [Account]
    let buttonTitle: String
    let action: (String) -> Void
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { isOpen.toggle() } } label: {
                HStack {
                    Label(title, systemImage: icon)
                    Spacer()
                    Text("\(accounts.count)").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                }
                ForEach(accounts) { account in
                    Divider().padding(.vertical, 10)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.institution).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(buttonTitle) { withAnimation { action(account.id) } }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("\(buttonTitle) \(account.name)")
                    }
                }
            }
        }
        .card()
    }
}

/// Shown when a bank stops sending new activity or SimpleFIN reports a
/// problem, so a missing purchase has an explanation and a fix.
private struct BankHealthCard: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        let stale = store.staleAccounts
        let errors = store.data.syncErrors ?? []
        if !stale.isEmpty || !errors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                ForEach(errors, id: \.self) { Text($0).font(.footnote) }
                if !stale.isEmpty {
                    Text(staleText(stale)).font(.footnote).foregroundStyle(.secondary)
                }
                Link("Open SimpleFIN Bridge", destination: URL(string: "https://bridge.simplefin.org")!)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var title: String {
        let banks = Set(store.staleAccounts.map(\.institution))
        return banks.count == 1 ? "\(banks.first!) isn’t sending new activity" : "A bank connection needs attention"
    }

    private func staleText(_ stale: [Account]) -> String {
        let oldest = stale.compactMap(\.bankUpdated).min()
        let since = oldest.map { "since \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "lately"
        return "Nothing new \(since). Open SimpleFIN Bridge and tap Adjust (or sign in again) on that bank; purchases fill in on the next sync."
    }
}
