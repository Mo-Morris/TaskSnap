import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskBoardView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var pasteCommandDispatcher: PasteCommandDispatcher
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false
    @State private var previewTask: TaskItem?
    @State private var inputAlert: InputAlert?
    @FocusState private var isPasteTargetFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDropTargeted ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isDropTargeted ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("多任务并行备忘录")
                    .font(.headline)
                Text("\(store.tasks.filter { !$0.isDone }.count) 个任务进行中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.clearCompleted()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .help("清空已完成任务")
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(Color.black.opacity(0.08))
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
            inputAlert = .missingVisionConfiguration
            return
        }

        if !store.addImageFromPasteboard() {
            inputAlert = .addFailed("剪贴板里没有可识别的图片。")
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                TaskRowIconButton(
                    systemName: task.isDone ? "checkmark.circle.fill" : "circle",
                    foregroundStyle: task.isDone ? .green : .secondary,
                    help: task.isDone ? "标记为未完成" : "划掉任务",
                    action: onToggle
                )

                TaskRowIconButton(
                    systemName: "trash",
                    foregroundStyle: .secondary,
                    help: "删除任务",
                    action: onDelete
                )
            }

            if let image = NSImage(data: task.imageData) {
                Button(action: onPreview) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 112)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(task.isDone ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .help("点击放大截图")
            }
        }
        .padding(10)
        .background(Color(hex: task.backgroundColorHex).opacity(task.isDone ? 0.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
