import SwiftUI

/// Explains why an in-place update stopped; a failed install also links to the release page.
@MainActor
struct UpdateFailureRow: View {
    let failure: UpdateChecker.InstallFailure
    let l: L
    let openReleasePage: () -> Void

    private var message: String {
        switch failure {
        case .busy: l.updateBusy
        case .failed: l.updateFailed
        case .restartRequired: l.updateRestartRequired
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if failure == .failed {
                Button(l.openReleasePage, action: openReleasePage).controlSize(.small)
            }
        }
    }
}
