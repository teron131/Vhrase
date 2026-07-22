// Presents semantic guidance, completion, warning, and failure messages.

import SwiftUI

struct NoticeCard: View {
    let text: String
    let systemImage: String
    let color: Color
    var title: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        _ text: String,
        systemImage: String,
        color: Color,
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: title == nil ? 0 : 2) {
                if let title {
                    Text(title)
                        .font(.callout.weight(.semibold))
                }
                Text(text)
                    .font(VhraseFont.micro)
                    .foregroundStyle(title == nil ? color : VhraseTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
