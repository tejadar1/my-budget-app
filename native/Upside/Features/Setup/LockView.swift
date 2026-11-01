import LocalAuthentication
import SwiftUI

/// Optional Face ID lock: covers the app until you unlock it.
struct LockView: View {
    let onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            AppIconView(size: 72)
            Text("Upside is locked").font(.title3.bold())
            Button {
                Task { await unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(minWidth: 160, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            if failed {
                Text("Couldn’t confirm it’s you. Try again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await unlock() }
    }

    private func unlock() async {
        let context = LAContext()
        // Face ID, falling back to the passcode.
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Unlock your budget")) ?? false
        if ok { onUnlock() } else { failed = true }
    }
}
