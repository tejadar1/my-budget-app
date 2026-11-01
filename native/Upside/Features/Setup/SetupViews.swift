import SwiftUI

/// "Set up Upside": what has to happen, in order, before the app shows your
/// real numbers. Each step ticks itself off.
struct SetupCard: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage("setupHidden") private var isHidden = false
    @State private var showConnect = false

    private var steps: [(title: String, detail: String, done: Bool)] {
        [
            ("Your names", "So Upside can show who spent what.", store.people.isSetUp),
            ("Connect your banks", "One SimpleFIN connection covers both of you.", store.data.bankConnected),
            ("Whose accounts", "Tap whose each account is.",
             !store.data.accounts.isEmpty && store.unclaimedAccounts.isEmpty),
        ]
    }

    var body: some View {
        let current = steps.firstIndex { !$0.done }
        if let current, !isHidden, !store.isDemo {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Set up Upside").font(.title3.bold())
                    Spacer()
                    Text("\(steps.filter { $0.done }.count) of \(steps.count) done")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(step.done || index == current ? Theme.accent : Color(.systemFill))
                            if step.done {
                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)").font(.footnote.bold())
                                    .foregroundStyle(index == current ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                            }
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                                .strikethrough(step.done)
                                .foregroundStyle(step.done ? .secondary : .primary)
                            Text(step.detail).font(.footnote).foregroundStyle(.secondary)
                            if index == current && index == 1 {
                                Button("Connect banks") { showConnect = true }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
                Button("Set up later") { isHidden = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .card(padding: 18)
            .sheet(isPresented: $showConnect) { ConnectBanksView() }
        }
    }
}

/// Both names, typed once.
struct PeopleCard: View {
    @Environment(BudgetStore.self) private var store
    @Binding var isEditing: Bool
    @State private var p1 = ""
    @State private var p2 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who’s budgeting?").font(.title3.bold())
                Text("Type your names so Upside can show who spent what.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            nameField(.p1, "Your name", $p1)
            nameField(.p2, "Partner’s name", $p2)
            HStack {
                if store.people.isSetUp {
                    Button("Cancel") { isEditing = false }
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    store.setNames(p1, p2)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(p1.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .card(padding: 20)
        .onAppear {
            p1 = store.people.p1
            p2 = store.people.p2
        }
    }

    private func nameField(_ owner: Owner, _ label: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(text.wrappedValue.isEmpty ? (owner == .p1 ? "1" : "2")
                 : String(text.wrappedValue.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(owner.ink)
                .frame(width: 36, height: 36)
                .background(owner.color, in: Circle())
            TextField(label, text: text)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Connecting banks: link them at SimpleFIN, copy a setup token, paste it
/// here. Every account it can see is added automatically.
struct ConnectBanksView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Upside reads your banks through SimpleFIN (about $15 a year). Either of you can link your banks there; one connection covers everything.",
                              systemImage: "building.columns")
                    }
                    .font(.subheadline)
                }
                Section("1. Link your banks") {
                    Button {
                        openURL(SimpleFIN.signUpURL)
                    } label: {
                        Label("Open SimpleFIN", systemImage: "arrow.up.right.square")
                    }
                    Text("Sign up, connect each bank and card, then choose “New Connection” → “Setup token” and copy it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("2. Paste your setup token") {
                    TextField("Setup token", text: $token, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        if let pasted = UIPasteboard.general.string { token = pasted }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.over) }
                }
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView().padding(.trailing, 6) }
                            Text(isWorking ? "Connecting…" : "Connect and add my accounts").bold()
                            Spacer()
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            .navigationTitle("Connect your banks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func connect() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await BankSync.connect(setupToken: token, store: store)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
