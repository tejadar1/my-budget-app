import SwiftUI

/// Laid out like the iOS Settings app.
struct SettingsView: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage("appearance") private var appearance: Appearance = .automatic
    @State private var showConnect = false
    @State private var showLimits = false
    @State private var editingNames = false
    @AppStorage("faceIDLock") private var faceIDLock = false
    @State private var confirmResort = false
    @State private var resortResult: String?
    @AppStorage("alertsLimits") private var limitAlerts = true
    @AppStorage("alertsWeekly") private var weeklySummary = true

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
                    row("Last synced", icon: "arrow.triangle.2.circlepath", color: .green,
                        value: store.data.lastBankSync?.formatted(.relative(presentation: .named)) ?? "Never",
                        chevron: false)
                } header: {
                    Text("Banks")
                } footer: {
                    Text("Accounts sync when you open Upside. Pull down on Accounts to sync right away.")
                }

                Section {
                    Button { showLimits = true } label: {
                        row("Monthly limits", icon: "chart.bar.fill", color: Theme.accent)
                    }
                    NavigationLink {
                        ReviewView()
                    } label: {
                        row("Purchases to sort", icon: "tray.full.fill", color: .orange,
                            value: store.uncategorized.isEmpty ? nil : "\(store.uncategorized.count)",
                            chevron: false)
                    }
                    Button { confirmResort = true } label: {
                        row("Re-sort all purchases", icon: "arrow.triangle.2.circlepath", color: .indigo,
                            chevron: false)
                    }
                    .confirmationDialog("Re-sort all purchases?", isPresented: $confirmResort, titleVisibility: .visible) {
                        Button("Re-sort all purchases") {
                            let unsorted = withAnimation { store.resortAllPurchases() }
                            resortResult = unsorted == 0 ? "Every purchase was sorted."
                                : "\(unsorted) purchase\(unsorted == 1 ? "" : "s") need\(unsorted == 1 ? "s" : "") you in Purchases to sort."
                        }
                    } message: {
                        Text("Upside forgets every category you picked and your “use for all” choices, then sorts everything again with its latest store lists. Banks, names, limits and trips stay.")
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    if let resortResult { Text(resortResult) }
                }

                Section {
                    Toggle(isOn: $limitAlerts) {
                        Label("Nearing a limit", systemImage: "bell.badge.fill")
                    }
                    Toggle(isOn: $weeklySummary) {
                        Label("Weekly summary", systemImage: "calendar")
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("A heads-up at 80% and 100% of a limit, and a Sunday-evening summary.")
                }
                .onChange(of: limitAlerts) { _, on in if on { Task { _ = await Alerts.requestPermission() } } }
                .onChange(of: weeklySummary) { _, on in if on { Task { _ = await Alerts.requestPermission() } } }

                Section {
                    Toggle(isOn: $faceIDLock) {
                        Label("Require Face ID", systemImage: "faceid")
                    }
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
