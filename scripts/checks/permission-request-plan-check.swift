// Verifies optional macOS permissions always register Vhrase before opening the matching Settings pane.

import Foundation

@main
struct PermissionRequestPlanCheck {
    static func main() {
        precondition(
            OptionalPermissionRequestPlan.steps(
                isGranted: false,
                requestedBefore: false
            ) == [.requestSystemAccess]
        )
        precondition(
            OptionalPermissionRequestPlan.steps(
                isGranted: false,
                requestedBefore: true
            ) == [.requestSystemAccess, .openSettingsIfRequestDenied]
        )
        precondition(
            OptionalPermissionRequestPlan.steps(
                isGranted: true,
                requestedBefore: true
            ).isEmpty
        )
        print("permission request plan ok")
    }
}
