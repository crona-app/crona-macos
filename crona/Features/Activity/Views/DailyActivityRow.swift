import SwiftUI

struct DailyActivityRow: View {
    let operation: CronaIssueOperation
    let title: String
    let time: String
    let isLast: Bool
    let openIssue: (() -> Void)?
    @State private var isHovered = false

    private var tint: Color {
        switch operation.action {
        case "create", "restore": return PopupVisualTheme.semantic(.success)
        case "delete": return PopupVisualTheme.semantic(.error)
        default:
            if let status = operation.payload?["to"]?.stringValue ?? operation.payload?["status"]?.stringValue {
                return CronaIssueStatusPresentation.color(for: status)
            }
            return PopupVisualTheme.semantic(.info)
        }
    }
    private var icon: String {
        switch operation.action {
        case "create": return "plus"
        case "restore": return "arrow.uturn.backward"
        case "delete": return "trash"
        default:
            if operation.payload?["todoForDate"] != nil { return "calendar" }
            if let status = operation.payload?["to"]?.stringValue ?? operation.payload?["status"]?.stringValue {
                return CronaIssueStatusPresentation.icon(for: status)
            }
            return "pencil"
        }
    }

    var body: some View {
        Group {
            if let openIssue {
                Button(action: openIssue) { content }
                    .buttonStyle(.plain)
                    .help("Open issue details")
            } else {
                content
            }
        }
        .background(alignment: .leading) {
            if !isLast {
                Rectangle().fill(.secondary.opacity(0.16)).frame(width: 1)
                    .padding(.top, 27).padding(.leading, 14)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(operation.actionLabel).font(.caption2).foregroundStyle(tint)
            }
            .padding(.top, 2)
            if openIssue != nil {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary).opacity(isHovered ? 1 : 0.35).padding(.top, 6)
            }
        }
        .padding(.horizontal, 3).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovered && openIssue != nil ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
