import SwiftUI

enum TaskFormPalette {
    static let background = Color(red: 41 / 255, green: 41 / 255, blue: 41 / 255)
    static let fieldBackground = Color.white.opacity(0.075)
    static let focusedFieldBackground = Color.white.opacity(0.095)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.58)
    static let border = Color.white.opacity(0.12)
    static let focusedBorder = Color.white.opacity(0.24)
    static let closeFill = Color.white.opacity(0.115)
    static let closeHoverFill = Color.white.opacity(0.17)
}

struct TaskFormHeader: View {
    let title: String
    let onClose: () -> Void

    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TaskFormPalette.primaryText)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TaskFormPalette.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(isHoveringClose ? TaskFormPalette.closeHoverFill : TaskFormPalette.closeFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help("关闭")
        }
    }
}

struct TaskFormLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TaskFormPalette.secondaryText)
    }
}

struct TaskFormTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .foregroundStyle(TaskFormPalette.primaryText)
            .scrollContentBackground(.hidden)
            .padding(9)
            .frame(height: 126)
            .background(TaskFormPalette.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TaskFormPalette.border, lineWidth: 1)
            }
            .environment(\.colorScheme, .dark)
    }
}

struct TaskFormPanelModifier: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(28)
            .frame(width: width)
            .background(TaskFormPalette.background)
            .foregroundStyle(TaskFormPalette.primaryText)
            .preferredColorScheme(.dark)
    }
}

struct TaskFormTextFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(TaskFormPalette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isFocused ? TaskFormPalette.focusedFieldBackground : TaskFormPalette.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isFocused ? TaskFormPalette.focusedBorder : TaskFormPalette.border, lineWidth: isFocused ? 1.5 : 1)
            }
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func taskFormPanel(width: CGFloat) -> some View {
        modifier(TaskFormPanelModifier(width: width))
    }

    func taskFormTextField(isFocused: Bool) -> some View {
        modifier(TaskFormTextFieldModifier(isFocused: isFocused))
    }
}
