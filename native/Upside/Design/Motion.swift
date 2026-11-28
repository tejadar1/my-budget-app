import SwiftUI
import UIKit

extension AnyTransition {
    /// Slides in from `edge` with a fade, or only fades when the person has
    /// turned on Reduce Motion (Settings › Accessibility › Motion), the way
    /// Apple's own apps swap movement for a dissolve.
    static func slide(from edge: Edge) -> AnyTransition {
        UIAccessibility.isReduceMotionEnabled ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
