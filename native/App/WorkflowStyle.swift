import SwiftUI
import RelayCore

// Plain, high-contrast controls with the same hierarchy on phone and Mac.
struct WorkflowHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.largeTitle.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty { Text(subtitle).font(.body).foregroundStyle(RelayTheme.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).padding(.bottom, 14)
    }
}
struct WorkflowSection: View {
    let title: String
    let symbol: String // Retains old call sites; decorative section symbols are intentionally not drawn.
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(RelayTheme.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct WorkflowInput: TextFieldStyle {
    @AppStorage("relay.highContrast") private var highContrast = false
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.body).padding(.horizontal, 12).padding(.vertical, 13).frame(minHeight: 46)
            .background(RelayTheme.incoming, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: highContrast ? 3 : 1.5))
    }
}
struct WorkflowSecondaryButton: ButtonStyle {
    @AppStorage("relay.highContrast") private var highContrast = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.bold)).multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(enabled ? Color.primary : .secondary)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(enabled ? 1 : 0.15), lineWidth: highContrast ? 3 : 1.5))
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
struct WorkflowBadge: View {
    let text: String
    var symbol = "clock"
    var color: Color = RelayTheme.accent
    var body: some View {
        Text(text).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true).foregroundStyle(color)
    }
}
struct WorkflowNotice: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(RelayTheme.accent).frame(width: 2)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
    }
}
struct WorkflowField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text).textFieldStyle(WorkflowInput()).focused(focus).accessibilityLabel(title)
        }
    }
}
struct WorkflowRequestCard: View {
    let record: CloudQueueRecord
    let shelter: String
    private var item: String { record.submission.structured_fields?.item_id ?? record.result?.result?.proposal?.item_id ?? "other" }
    private var quantity: String? { (record.submission.structured_fields?.quantity ?? record.result?.result?.proposal?.quantity).map(String.init) }
    private var closed: Bool { ["cancelled", "rejected", "completed"].contains(record.history?.status ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelter.uppercased()).font(.system(.caption2, design: .monospaced)).tracking(0.5).foregroundStyle(RelayTheme.secondary)
                Spacer()
                Text(record.submission.created_at, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(RelayTheme.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(InventoryItem.title(item)).font(.title3.weight(.semibold))
                Spacer(minLength: 12)
                if let quantity { Text(quantity).font(.system(.title2, design: .monospaced).weight(.medium)) }
            }
            if let urgency = record.submission.structured_fields?.urgency.flatMap(RequestUrgency.init(rawValue:)) { Text(urgency.title + " · reported urgency").font(.caption.bold()) }
            Text(record.submission.original_text).font(.subheadline).foregroundStyle(RelayTheme.secondary).lineLimit(2)
            HStack {
                WorkflowBadge(text: WorkflowRequestsView.progress(record), color: closed ? .secondary : RelayTheme.accent)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(RelayTheme.secondary).accessibilityHidden(true)
            }
            Divider().padding(.top, 10)
        }.padding(.top, 14).multilineTextAlignment(.leading).contentShape(Rectangle())
    }
}
struct WorkflowFilter: View {
    @Binding var selection: String
    let options: [String]
    var body: some View {
        HStack(spacing: 24) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    VStack(spacing: 10) {
                        Text(option).font(.subheadline.weight(selection == option ? .semibold : .regular))
                            .foregroundStyle(selection == option ? .primary : .secondary)
                        Rectangle().fill(selection == option ? RelayTheme.action : .clear).frame(height: 2)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5) }
    }
}

struct WorkflowFact: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title).foregroundStyle(RelayTheme.secondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).foregroundStyle(.black).multilineTextAlignment(.trailing)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}
