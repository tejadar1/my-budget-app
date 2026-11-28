import SwiftUI

@main
struct UpsideApp: App {
    @UIApplicationDelegateAdaptor(UpsideAppDelegate.self) private var appDelegate
    @State private var store: BudgetStore
    @AppStorage("appearance") private var appearance: Appearance = .automatic

    init() {
        let args = ProcessInfo.processInfo.arguments
        // `-demo` (screenshots, "Try the demo") uses sample data and never saves.
        if args.contains("-demo") {
            _store = State(initialValue: BudgetStore(data: DemoData.make(), isDemo: true))
        } else {
            _store = State(initialValue: BudgetStore.load())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
                .task { CloudSync.shared.start(store) }
        }
        // iOS wakes Upside now and then to sync banks and send alerts.
        .backgroundTask(.appRefresh(Alerts.refreshTaskId)) { [store] in
            await Alerts.backgroundRefresh(store)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// `-open category:groceries` (etc.) jumps to a screen; used for screenshots.
enum LaunchArgs {
    static var open: (kind: String, id: String)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-open"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ":", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : "")
    }
}

enum AppTab: String, Hashable {
    case budget, transactions, accounts, settings
}

struct RootView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("faceIDLock") private var lockEnabled = false
    @State private var tab: AppTab = {
        // `-tab accounts` opens a specific tab (used for screenshots).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
           let tab = AppTab(rawValue: args[i + 1]) {
            return tab
        }
        return .budget
    }()

    var body: some View {
        TabView(selection: $tab) {
            BudgetView()
                .tabItem { Label("Budget", systemImage: "chart.bar.fill") }
                .tag(AppTab.budget)
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard.fill") }
                .tag(AppTab.accounts)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .bottom) { UndoToast() }
        // Bank sync runs whenever Upside comes to the front (at most hourly).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task {
                if !store.isDemo { store.recordMonthSnapshot(); store.creditGoals(); store.stepLimits() }
                await autoSync()
                // Pick up the other phone's changes each time Upside opens.
                await CloudSync.shared.pull()
            }
            case .background:
                if lockEnabled && !store.isDemo { LockScreen.show() }
                Alerts.scheduleRefresh()
            default: break
            }
        }
        .task {
            if lockEnabled && !store.isDemo { LockScreen.show() }
            // Budgets connected before alerts existed were never asked.
            if !store.isDemo && BankSync.isConnected { _ = await Alerts.requestPermission() }
            await autoSync()
        }
    }

    private func autoSync() async {
        guard !store.isDemo, BankSync.isConnected else { return }
        if let last = store.data.lastBankSync, Date().timeIntervalSince(last) < 3600 { return }
        try? await BankSync.sync(store: store)
        await Alerts.check(store)
    }
}

/// "Paid · Undo": a few seconds to take back a one-tap change.
struct UndoToast: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if let item = store.undo {
            HStack(spacing: 14) {
                Text(item.label).font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") {
                    Haptics.tap()
                    withAnimation { store.undoLast() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 16).padding(.bottom, 96)
            .transition(.slide(from: .bottom))
            .task(id: item.id) {
                try? await Task.sleep(for: .seconds(6))
                withAnimation { if store.undo?.id == item.id { store.undo = nil } }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
