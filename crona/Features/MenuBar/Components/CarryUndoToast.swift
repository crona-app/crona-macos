import SwiftUI

/// Short-lived "Carried … to tomorrow · Undo" strip, plus any carry error.
struct CarryUndoToast: View {
    @ObservedObject private var carryOver: CarryOverModel

    init(carryOver: CarryOverModel) {
        self._carryOver = ObservedObject(wrappedValue: carryOver)
    }

    var body: some View {
        if let offer = carryOver.undoOffer {
            HStack(spacing: 7) {
                Image(systemName: CronaCarryPresentation.carriedIcon)
                    .foregroundStyle(CronaCarryPresentation.carriedColor)
                Text(CronaCarryPresentation.undoMessage(title: offer.title))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Undo") {
                    Task { await carryOver.undo() }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CronaCarryPresentation.carriedColor)
            }
            .font(.caption)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.82))
            .padding(.horizontal, 4)
        } else if let error = carryOver.errorMessage {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.warning))
                Text(error)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    carryOver.clearError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .menuBarIconHitTarget()
            }
            .font(.caption)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
            .padding(.horizontal, 4)
        }
    }
}
