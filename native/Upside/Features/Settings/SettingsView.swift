import SwiftUI

/// Laid out like the iOS Settings app.
struct SettingsView: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage("appearance") private var appearance: Appearance = .automatic
    @State private var showConnect = false
    @State private var showLimits = false
    @State private var showBridge = false
    @State private var editingNames = false
    @AppStorage("faceIDLock") private var faceIDLock = false
    @State private var confirmResort = false
    @State private var confirmResortAgain = false
    @State private var resortResult: String?
    @AppStorage("alertsLimits") private var limitAlerts = true
    @AppStorage("alertsWeekly") private var weeklySummary = true
    @AppStorage("alertsBills") private var billAlerts = true
    @AppStorage("alertsLowBalance") private var lowBalanceAlerts = true
    @AppStorage("alertsLowBalanceAt") private var lowBalanceAt = 500
    @AppStorage("alertsLarge") private var largeAlerts = true
    @AppStorage("alertsLargeAt") private var largeAt = 300

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(size: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upside").font(.title2.weight(.semibold))
                            Text(store.isDemo ? "Demo budget" : "Smart money, together.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("People") {
                    if editingNames || !store.people.isSetUp {
                        PeopleCard(isEditing: $editingNames)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach([Owner.p1, .p2].filter { !store.people.name($0).isEmpty }) { owner in
                            Button { editingNames = true } label: {
                                HStack(spacing: 12) {
                                    OwnerBadge(owner: owner, people: store.people, size: 29)
                                    Text(store.people.name(owner)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { showConnect = true } label: {
                        row("Bank connection", icon: "building.columns.fill", color: .teal,
                            value: store.data.bankConnected ? "Connected" : "Not connected")
                    }
                    if store.data.bankConnected {
                        Button { showBridge = true } label: {
                            row("Manage banks", icon: "slider.horizontal.3", color: .blue)
                        }
                    }
                    row("Last synced", icon: "arrow.triangle.2.circlepath", color: .green,
                        value: store.data.lastBankSync?.formatted(.relative(presentation: .named)) ?? "Never",
                        chevron: false)
                } header: {
                    Text("Banks")
                } footer: {
                    Text("Manage banks opens SimpleFIN: add a bank, sign in again, or tap Adjust. Upside syncs when you close it.")
                }

                if !store.isDemo {
                    ICloudSection()
                }

                Section {
                    Button { showLimits = true } label: {
                        row("Categories", icon: "square.grid.2x2.fill", color: Theme.accent)
                    }
                    NavigationLink {
                        ReviewView()
                    } label: {
                        row("Purchases to check", icon: "tray.full.fill", color: .orange,
                            value: store.toCheck.isEmpty ? nil : "\(store.toCheck.count)",
                            chevron: false)
                    }
                    Toggle(isOn: Binding(get: { store.data.tripsOff != true },
                                         set: { on in store.data.tripsOff = on ? nil : true })) {
                        row("Plan for trips", icon: "airplane", color: .cyan, chevron: false)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Budget")
                }

                Section {
                    // Green switches and colored icons, like the rest of Settings.
                    Toggle(isOn: $limitAlerts) {
                        row("Nearing a limit", icon: "bell.badge.fill", color: .red, chevron: false)
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $billAlerts) {
                        row("Bills due soon", icon: "calendar.badge.clock", color: .orange, chevron: false)
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $lowBalanceAlerts) {
                        row("Low checking balance", icon: "exclamationmark.triangle.fill", color: .yellow, chevron: false)
                    }
                    .tint(Theme.accent)
                    if lowBalanceAlerts {
                        Picker("Warn under", selection: $lowBalanceAt) {
                            ForEach([250, 500, 1_000, 2_000], id: \.self) { Text(Money.short($0 * 100)).tag($0) }
                        }
                    }
                    Toggle(isOn: $largeAlerts) {
                        row("Large purchases", icon: "creditcard.fill", color: .purple, chevron: false)
                    }
                    .tint(Theme.accent)
                    if largeAlerts {
                        Picker("Over", selection: $largeAt) {
                            ForEach([100, 200, 300, 500, 1_000], id: \.self) { Text(Money.short($0 * 100)).tag($0) }
                        }
                    }
                    Toggle(isOn: $weeklySummary) {
                        row("Weekly summary", icon: "calendar", color: .blue, chevron: false)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Bills: 9am two days before they’re due. Low balance: when checking dips under your amount or under bills still due.")
                }
                .onChange(of: limitAlerts) { _, on in if on { Task { _ = await Alerts.requestPermission() } } }
                .onChange(of: weeklySummary) { _, on in if on { Task { _ = await Alerts.requestPermission() } } }
                .onChange(of: billAlerts) { _, on in
                    Task { if on { _ = await Alerts.requestPermission() }; await Alerts.scheduleBillReminders(store) }
                }

                Section {
                    Toggle(isOn: $faceIDLock) {
                        row("Require Face ID", icon: "faceid", color: .green, chevron: false)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Asks for Face ID (or your passcode) when you open Upside.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sharing") {
                    row("Share with your partner", icon: "person.2.fill", color: .blue,
                        value: "Coming soon", chevron: false)
                }

                // Start over: kept apart at the bottom, two confirmations.
                Section {
                    Button(role: .destructive) { confirmResort = true } label: {
                        Label("Re-sort all purchases", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.over)
                    }
                    .confirmationDialog("Re-sort all purchases?", isPresented: $confirmResort, titleVisibility: .visible) {
                        Button("Continue", role: .destructive) { confirmResortAgain = true }
                    } message: {
                        Text("Upside forgets every category you picked and every “sort all” choice, then sorts everything again from its store lists. Banks, names, limits and trips stay.")
                    }
                    .alert("Are you sure?", isPresented: $confirmResortAgain) {
                        Button("Cancel", role: .cancel) { }
                        Button("Re-sort everything", role: .destructive) {
                            let left = withAnimation { store.resortAllPurchases() }
                            resortResult = left == 0 ? "Every purchase was sorted."
                                : "\(left) purchase\(left == 1 ? "" : "s") to check."
                        }
                    } message: {
                        Text("This can’t be undone.")
                    }
                } header: {
                    Text("Start over")
                } footer: {
                    Text(resortResult ?? "Only if sorting has gone wrong. Your own choices are lost.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Upside \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .frame(maxWidth: .infinity)
                }
            }
            .tint(.primary)
            .navigationTitle("Settings")
            .sheet(isPresented: $showConnect) { ConnectBanksView() }
            .sheet(isPresented: $showLimits) { LimitsView() }
            .sheet(isPresented: $showBridge, onDismiss: { Task { try? await BankSync.sync(store: store) } }) {
                SafariSheet(url: SimpleFIN.manageURL).ignoresSafeArea()
            }
        }
    }

    /// An iOS Settings row: colored icon tile, label, value, chevron.
    private func row(_ title: String, icon: String, color: Color,
                     value: String? = nil, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// iCloud backup and sharing the budget with your partner.
private struct ICloudSection: View {
    @Environment(BudgetStore.self) private var store
    private var cloud: CloudSync { CloudSync.shared }
    @State private var confirmLeave = false

    var body: some View {
        Section {
            LabeledContent {
                Text(statusText).foregroundStyle(statusIsProblem ? Theme.over : .secondary)
            } label: {
                Label("iCloud backup", systemImage: "icloud.fill")
            }
            if cloud.isParticipant {
                Button("Leave shared budget", role: .destructive) { confirmLeave = true }
                    .confirmationDialog("Leave the shared budget?", isPresented: $confirmLeave, titleVisibility: .visible) {
                        Button("Leave", role: .destructive) { Task { await cloud.leave() } }
                    } message: {
                        Text("This phone keeps a copy, but changes stop syncing with the other phone.")
                    }
            } else if CloudSync.isAvailable {
                Button {
                    Task { await cloud.presentSharing() }
                } label: {
                    Label(shareTitle, systemImage: "person.2.fill")
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(footer)
        }
    }

    private var partner: String {
        store.people.p2.isEmpty ? "your partner" : store.people.p2
    }

    private var shareTitle: String {
        let joined = (cloud.share?.participants.count ?? 1) > 1
        return joined ? "Shared with \(partner) · Manage" : "Share budget with \(partner)"
    }

    private var footer: String {
        switch cloud.status {
        case .failed(let why), .off(let why) where why != "Not started": return why
        default: break
        }
        if cloud.isParticipant { return "You’re using a budget shared with you. Changes sync both ways." }
        return "Your budget is backed up to your iCloud. Sharing lets \(partner) see and edit it on their iPhone; your phone keeps syncing the banks."
    }

    private var statusText: String {
        switch cloud.status {
        case .off: return "Off"
        case .syncing: return "Syncing…"
        case .synced(let date): return "Backed up " + date.formatted(.relative(presentation: .named))
        case .failed: return "Problem"
        }
    }

    private var statusIsProblem: Bool {
        if case .failed = cloud.status { return true }
        return false
    }
}
