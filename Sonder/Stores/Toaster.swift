import SwiftUI

/// App-wide transient messages (errors, confirmations), shown as a banner by `ToastOverlay`.
@MainActor
final class Toaster: ObservableObject {
    static let shared = Toaster()

    enum Style {
        case info, success, error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Style = .info) {
        let toast = Toast(message: message, style: style)
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: style == .error ? 4_500_000_000 : 2_800_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast)
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func error(_ error: Error) {
        // Cancellation is expected (view disappeared, newer request superseded this one).
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        show(ErrorCopy.message(for: error), style: .error)
    }

    func dismiss(_ toast: Toast? = nil) {
        guard toast == nil || toast == current else { return }
        current = nil
    }
}

/// Banner that slides down from the top of the screen.
struct ToastOverlay: View {
    @ObservedObject var toaster: Toaster

    var body: some View {
        VStack {
            if let toast = toaster.current {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: toast.style.icon)
                        .foregroundStyle(color(for: toast.style))
                    Text(toast.message)
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderTextPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color.sonderSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.sonderDivider, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { toaster.dismiss() }
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toaster.current)
    }

    private func color(for style: Toaster.Style) -> Color {
        switch style {
        case .info: return .sonderSage
        case .success: return .sonderSage
        case .error: return .sonderDanger
        }
    }
}
