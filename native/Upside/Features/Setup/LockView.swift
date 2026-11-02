import LocalAuthentication
import SwiftUI
import UIKit

/// Shows LockView in its own window above everything, including sheets
/// that were open when you left the app.
@MainActor
enum LockScreen {
    private static var window: UIWindow?

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.rootViewController = UIHostingController(rootView: LockView { hide() }.tint(Theme.accent))
        w.makeKeyAndVisible()
        window = w
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}

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
        // Ask only once the app is in front; asking from the background fails.
        .onAppear { if UIApplication.shared.applicationState == .active { Task { await unlock() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await unlock() }
        }
    }

    @State private var isAsking = false

    private func unlock() async {
        guard !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        failed = false
        let context = LAContext()
        // Face ID, falling back to the passcode.
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Unlock your budget")) ?? false
        if ok { onUnlock() } else { failed = true }
    }
}
