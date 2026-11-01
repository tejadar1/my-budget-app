import SwiftUI

@main
struct UpsideApp: App {
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
    case budget, accounts, settings
}

struct RootView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("faceIDLock") private var lockEnabled = false
    @State private var isLocked = UserDefaults.standard.bool(forKey: "faceIDLock")
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
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard.fill") }
                .tag(AppTab.accounts)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .overlay {
            if isLocked && lockEnabled && !store.isDemo {
                LockView { isLocked = false }
            }
        }
        // Bank sync runs whenever Upside comes to the front (at most hourly).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await autoSync() }
            case .background:
                if lockEnabled { isLocked = true }
                Alerts.scheduleRefresh()
            default: break
            }
        }
        .task { await autoSync() }
    }

    private func autoSync() async {
        guard !store.isDemo, BankSync.isConnected else { return }
        if let last = store.data.lastBankSync, Date().timeIntervalSince(last) < 3600 { return }
        try? await BankSync.sync(store: store)
        await Alerts.check(store)
    }
}
