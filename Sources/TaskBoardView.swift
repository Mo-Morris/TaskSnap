import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskBoardView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var pasteCommandDispatcher: PasteCommandDispatcher
    @Binding var isCollapsed: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false
    @State private var previewTask: TaskItem?
    @State private var inputAlert: InputAlert?
    @FocusState private var isPasteTargetFocused: Bool

    var body: some View {
        Group {
            if isCollapsed {
                CollapsedTaskIconView(
                    activeTaskCount: activeTaskCount,
                    isWorking: !store.summarizingTaskIDs.isEmpty
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isCollapsed = false
                    }
                }
            } else {
                expandedBoard
            }
        }
        .overlay {
            if !isCollapsed || isDropTargeted {
                RoundedRectangle(cornerRadius: isCollapsed ? 36 : 14)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color.white.opacity(0.18),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isCollapsed ? 36 : 14, style: .continuous))
        .onDrop(
            of: [UTType.image.identifier, UTType.fileURL.identifier, UTType.png.identifier, UTType.jpeg.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
        .onPasteCommand(of: [.image, .png, .jpeg, .tiff, .fileURL]) { providers in
            if providers.isEmpty {
                pasteImageFromPasteboard()
            } else {
                _ = handleDrop(providers: providers)
            }
        }
        .focusable()
        .focused($isPasteTargetFocused)
        .focusEffectDisabled()
        .onAppear {
            isPasteTargetFocused = true
        }
        .simultaneousGesture(TapGesture().onEnded {
            isPasteTargetFocused = true
        })
        .onChange(of: pasteCommandDispatcher.requestID) {
            pasteImageFromPasteboard()
        }
        .sheet(item: $previewTask) { task in
            ImagePreviewView(task: task)
        }
        .alert(inputAlert?.title ?? "", isPresented: Binding(
            get: { inputAlert != nil },
            set: { if !$0 { inputAlert = nil } }
        )) {
            if inputAlert?.opensSettings == true {
                Button("去配置") {
                    inputAlert = nil
                    openSettings()
                }

                Button("取消", role: .cancel) {}
            } else {
                Button("知道了", role: .cancel) {}
            }
        } message: {
            Text(inputAlert?.message ?? "")
        }
    }

    private var activeTaskCount: Int {
        store.tasks.filter { !$0.isDone }.count
    }

    private var expandedBoard: some View {
        VStack(spacing: 0) {
            if store.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(.regularMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text("把截图拖进来")
                .font(.title3.weight(.semibold))

            Text("拖入截图或按 Command-V 粘贴；首次使用请先配置视觉大模型")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                pasteImageFromPasteboard()
            } label: {
                Label("粘贴截图", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.tasks) { task in
                    TaskRow(task: task) {
                        store.toggle(task)
                    } onDelete: {
                        store.delete(task)
                    } onPreview: {
                        previewTask = task
                    }
                    .overlay(alignment: .topTrailing) {
                        if store.summarizingTaskIDs.contains(task.id) {
                            ProgressView()
                                .controlSize(.small)
                                .padding(8)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        if isCollapsed {
            isCollapsed = false
        }

        guard store.visionConfiguration != nil else {
            inputAlert = .missingVisionConfiguration
            return false
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        if !store.addImageData(data) {
                            inputAlert = .addFailed("截图添加失败，请确认图片格式可识别。")
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard
                        let data,
                        let url = URL(dataRepresentation: data, relativeTo: nil),
                        let imageData = try? Data(contentsOf: url)
                    else {
                        return
                    }

                    Task { @MainActor in
                        if !store.addImageData(imageData, title: url.deletingPathExtension().lastPathComponent) {
                            inputAlert = .addFailed("截图添加失败，请确认图片格式可识别。")
                        }
                    }
                }
                return true
            }
        }

        return false
    }

    private func pasteImageFromPasteboard() {
        guard store.visionConfiguration != nil else {
            isCollapsed = false
            inputAlert = .missingVisionConfiguration
            return
        }

        if !store.addImageFromPasteboard() {
            isCollapsed = false
            inputAlert = .addFailed("剪贴板里没有可识别的图片。")
        } else if isCollapsed {
            isCollapsed = false
        }
    }
}

private struct CollapsedTaskIconView: View {
    let activeTaskCount: Int
    let isWorking: Bool
    let onExpand: () -> Void

    @State private var isAnimating = false
    @State private var isHovered = false
    @State private var isHinting = false

    var body: some View {
        iconArtwork
            .frame(width: 64, height: 64)
            .overlay(alignment: .topTrailing) {
                if activeTaskCount > 0 {
                    activeTaskBadge
                        .offset(x: -2, y: 3)
                }
            }
            .padding(4)
            .scaleEffect(isHovered ? 1.04 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
            .contentShape(Circle())
            .onTapGesture(perform: onExpand)
            .onHover { isHovered = $0 }
            .help("展开任务列表")
            .accessibilityLabel("展开任务列表")
            .accessibilityValue(activeTaskCount > 0 ? "\(activeTaskCount) 个任务进行中" : "没有进行中的任务")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                isAnimating = isWorking
                isHinting = true
            }
            .onChange(of: isWorking) { _, newValue in
                if newValue {
                    isAnimating = false
                    DispatchQueue.main.async {
                        isAnimating = true
                    }
                } else {
                    isAnimating = false
                }
            }
    }

    private var iconArtwork: some View {
        ZStack {
            Circle()
                .fill(iconGradient)
                .scaleEffect(isHinting ? 1.18 : 0.92)
                .opacity(isHinting ? 0 : 0.24)
                .animation(.easeOut(duration: 1.7).repeatForever(autoreverses: false), value: isHinting)

            Circle()
                .fill(iconGradient)
                .shadow(color: Color(red: 0.54, green: 0.36, blue: 0.96).opacity(isHovered ? 0.28 : 0.18), radius: isHovered ? 16 : 12, y: 5)
                .shadow(color: Color.white.opacity(0.88), radius: 1, y: -1)
                .scaleEffect(isHinting ? 1.02 : 1)
                .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: isHinting)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.3))
                .frame(width: 30, height: 37)
                .rotationEffect(.degrees(-8))
                .offset(x: -4, y: 1)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .frame(width: 32, height: 38)
                .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)

            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(red: 0.61, green: 0.52, blue: 0.98).opacity(0.22))
                    .frame(width: 18, height: 12)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(red: 0.58, green: 0.42, blue: 0.96))
                    }

                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.24, green: 0.78, blue: 0.54))
                        .frame(width: 6, height: 6)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 0.58, green: 0.42, blue: 0.96).opacity(0.3))
                        .frame(width: 14, height: 5)
                }
            }
            .offset(y: 1)

            Image(systemName: "sparkle")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: Color(red: 0.43, green: 0.22, blue: 0.86).opacity(0.22), radius: 2, y: 1)
                .rotationEffect(.degrees(isWorking && isAnimating ? 360 : 0))
                .scaleEffect(isWorking && isAnimating ? 1.08 : 1)
                .offset(x: 13, y: -13)
                .animation(isWorking ? .linear(duration: 1.4).repeatForever(autoreverses: false) : .default, value: isAnimating)
        }
    }

    private var activeTaskBadge: some View {
        Text(activeTaskCount > 99 ? "99+" : "\(activeTaskCount)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(minWidth: activeTaskCount > 99 ? 28 : 20, minHeight: 20)
            .padding(.horizontal, activeTaskCount > 9 ? 4 : 0)
            .background(Color.red)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 3, y: 1)
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.62, green: 0.55, blue: 1.0),
                Color(red: 0.72, green: 0.48, blue: 0.98),
                Color(red: 0.46, green: 0.68, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum InputAlert {
    case missingVisionConfiguration
    case addFailed(String)

    var title: String {
        switch self {
        case .missingVisionConfiguration:
            "需要配置视觉大模型"
        case .addFailed:
            "无法添加截图"
        }
    }

    var message: String {
        switch self {
        case .missingVisionConfiguration:
            "保存截图前，请先配置可用的视觉大模型。配置通过测试后，再重新添加截图。"
        case .addFailed(let message):
            message
        }
    }

    var opensSettings: Bool {
        switch self {
        case .missingVisionConfiguration:
            true
        case .addFailed:
            false
        }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onPreview: () -> Void

    private var cardColor: Color {
        Color(hex: task.backgroundColorHex)
    }

    private var displayTitle: String {
        splitTitleAndDescription.title
    }

    private var displayDescription: String {
        splitTitleAndDescription.description
    }

    private var splitTitleAndDescription: (title: String, description: String) {
        let normalized = task.title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return ("未命名截图任务", "等待视觉模型补全截图里的任务线索。")
        }

        let separators = CharacterSet(charactersIn: "。！？!?；;，,")
        if let separatorRange = normalized.rangeOfCharacter(from: separators) {
            let title = String(normalized[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let descriptionStart = normalized.index(after: separatorRange.lowerBound)
            let description = String(normalized[descriptionStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !title.isEmpty, !description.isEmpty {
                return (title, description)
            }
        }

        if normalized.count > 18 {
            let splitIndex = normalized.index(normalized.startIndex, offsetBy: 18)
            let title = String(normalized[..<splitIndex])
            let description = String(normalized[splitIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, description.isEmpty ? "查看截图，快速回到这项任务的上下文。" : description)
        }

        return (normalized, "查看截图，快速回到这项任务的上下文。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.isDone ? "标记为未完成" : "划掉任务")

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(displayDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(task.isDone ? "已完成" : "进行中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(task.isDone ? Color.green : Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())

                    TaskRowIconButton(
                        systemName: "trash",
                        foregroundStyle: .secondary,
                        help: "删除任务",
                        action: onDelete
                    )
                }
            }

            if let image = NSImage(data: task.imageData) {
                Button(action: onPreview) {
                    ZStack(alignment: .bottomLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 156)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .opacity(task.isDone ? 0.5 : 1)

                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.34),
                                Color.black.opacity(0)
                            ],
                            startPoint: .bottom,
                            endPoint: .center
                        )

                        Label("查看截图", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.28))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                    .frame(height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .help("点击放大截图")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardColor.opacity(task.isDone ? 0.42 : 0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial.opacity(task.isDone ? 0.35 : 0.12))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(task.isDone ? 0.04 : 0.1), radius: 12, y: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskRowIconButton: View {
    let systemName: String
    let foregroundStyle: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(foregroundStyle)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ImagePreviewView: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("关闭")
            }
            .padding(14)

            if let image = NSImage(data: task.imageData) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                }
                .background(Color.black.opacity(0.06))
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct VisionModelSettingsView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingVisionConfiguration = false
    @State private var endpoint: String
    @State private var apiKey: String
    @State private var model: String
    @State private var isTesting = false
    @State private var errorMessage: String?

    init(store: TaskStore) {
        self.store = store
        let configuration = store.visionConfiguration
        _endpoint = State(initialValue: configuration?.endpoint ?? "")
        _apiKey = State(initialValue: configuration?.apiKey ?? "")
        _model = State(initialValue: configuration?.model ?? "")
    }

    var body: some View {
        ZStack {
            SettingsPalette.background.ignoresSafeArea()

            if isShowingVisionConfiguration {
                configurationPage
            } else {
                overviewPage
            }
        }
        .frame(width: 620, height: 420)
    }

    private var canSave: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader(title: "设置", subtitle: "管理 TaskSnap 的截图、任务和模型行为。")
                .padding(.bottom, 18)

            SettingsDivider()

            SettingsOptionRow(
                iconName: "brain.head.profile",
                title: "多模态大模型",
                subtitle: "配置用于总结截图内容的视觉模型，测试通过后才能保存截图任务。",
                status: store.visionConfiguration == nil ? "未配置" : "已配置",
                actionTitle: "配置"
            ) {
                syncFieldsFromStore()
                errorMessage = nil
                isShowingVisionConfiguration = true
            }

            SettingsDivider()

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
    }

    private var configurationPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button {
                    isShowingVisionConfiguration = false
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SettingsPalette.primaryText)
                .disabled(isTesting)

                Spacer()
            }

            settingsHeader(title: "多模态大模型", subtitle: "用于总结拖入或粘贴的截图内容，测试通过后才会保存。")
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 12) {
                TextField("接口地址，例如 https://api.openai.com", text: $endpoint)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("模型名，例如 gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            SettingsDivider()

            HStack {
                Button("清除配置", role: .destructive) {
                    store.clearVisionConfiguration()
                    syncFieldsFromStore()
                    isShowingVisionConfiguration = false
                }
                .disabled(store.visionConfiguration == nil || isTesting)

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .disabled(isTesting)

                Button {
                    save()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("测试并保存")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTesting || !canSave)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
    }

    private func settingsHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(SettingsPalette.primaryText)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondaryText)
        }
    }

    private func syncFieldsFromStore() {
        let configuration = store.visionConfiguration
        endpoint = configuration?.endpoint ?? ""
        apiKey = configuration?.apiKey ?? ""
        model = configuration?.model ?? ""
    }

    private func save() {
        isTesting = true
        errorMessage = nil
        let configuration = VisionModelConfiguration(endpoint: endpoint, apiKey: apiKey, model: model)

        Task {
            do {
                try await store.saveVisionConfiguration(configuration)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isTesting = false
        }
    }
}

private struct SettingsOptionRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    let status: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(SettingsPalette.accent)
                .frame(width: 36, height: 36)
                .background(SettingsPalette.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SettingsPalette.primaryText)

                    Text(status)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .background(SettingsPalette.badgeBackground)
                        .clipShape(Capsule())
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(.vertical, 20)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.divider)
            .frame(height: 1)
    }
}

private enum SettingsPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let badgeBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    static let divider = Color(nsColor: .separatorColor).opacity(0.65)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let accent = Color(nsColor: .secondaryLabelColor)
}

private extension Color {
    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(normalized, radix: 16) ?? 0xF8E7E0
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
