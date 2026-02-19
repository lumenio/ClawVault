import LocalAuthentication
import SwiftUI

/// SwiftUI sheet for admin confirmation + Touch ID.
/// Shown when the daemon requests admin approval via XPC callback.
struct AdminApprovalView: View {
    @ObservedObject var request: AdminApprovalRequest
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Admin Approval Required")
                .font(.headline)

            Text(request.summary)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .frame(maxWidth: 400)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button("Deny") {
                    request.completion(false)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Approve with Touch ID") {
                    authenticate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAuthenticating)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 200)
    }

    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            errorMessage = "Biometric authentication not available: \(authError?.localizedDescription ?? "unknown error")"
            isAuthenticating = false
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Approve Monolith admin action"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    request.completion(true)
                    dismiss()
                } else {
                    errorMessage = error?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }
}
