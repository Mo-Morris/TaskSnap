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
    @State private var isShowingManualTaskForm = false
    @State private var draggingTaskID: TaskItem.ID?
    @State private var dragVerticalOffset: CGFloat = 0
    @State private var reorderTargetIndex: Int?
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
                    .allowsHitTesting(false)
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
        .onChange(of: pasteCommandDispatcher.requestID) {
            pasteImageFromPasteboard()
        }
        .sheet(item: $previewTask) { task in
            ImagePreviewView(task: task)
        }
        .sheet(isPresented: $isShowingManualTaskForm) {
            ManualTaskFormView { title, description in
                store.addManualTask(title: title, description: description)
            }
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
            titleBar

            if store.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBar: some View {
        HStack {
            Spacer()

            Button {
                isShowingManualTaskForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.76))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("新建手动任务")
            .accessibilityLabel("新建手动任务")
        }
        .frame(height: 30)
        .padding(.horizontal, 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.09))
                .frame(height: 1)
        }
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
            LazyVStack(spacing: 14) {
                ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                    if reorderTargetIndex == index, draggingTaskID != nil {
                        ReorderInsertionIndicator()
                    }

                    TaskRow(
                        task: task,
                        isSummarizing: store.summarizingTaskIDs.contains(task.id)
                    ) {
                        store.toggle(task)
                    } onDelete: {
                        store.delete(task)
                    } onPreview: {
                        previewTask = task
                    } onReorderChanged: { verticalOffset in
                        updateReorderTarget(for: task, sourceIndex: index, verticalOffset: verticalOffset)
                    } onReorderEnded: {
                        finishReorder(for: task)
                    }
                    .offset(y: draggingTaskID == task.id ? dragVerticalOffset : 0)
                    .scaleEffect(draggingTaskID == task.id ? 1.012 : 1)
                    .zIndex(draggingTaskID == task.id ? 10 : 0)
                    .overlay(alignment: .topTrailing) {
                        if store.summarizingTaskIDs.contains(task.id) {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 22)
                                .padding(.trailing, 22)
                                .allowsHitTesting(false)
                        }
                    }
                }

                if reorderTargetIndex == store.tasks.count, draggingTaskID != nil {
                    ReorderInsertionIndicator()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func updateReorderTarget(for task: TaskItem, sourceIndex: Int, verticalOffset: CGFloat) {
        draggingTaskID = task.id
        dragVerticalOffset = verticalOffset

        let rowStep: CGFloat = 146
        let rawIndex = CGFloat(sourceIndex) + (verticalOffset / rowStep).rounded()
        reorderTargetIndex = min(max(Int(rawIndex), 0), store.tasks.count)
    }

    private func finishReorder(for task: TaskItem) {
        if let reorderTargetIndex {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                store.move(task, to: reorderTargetIndex)
            }
        }

        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            draggingTaskID = nil
            dragVerticalOffset = 0
            reorderTargetIndex = nil
        }
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
    @State private var didDrag = false

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
            .simultaneousGesture(dragDetectionGesture)
            .onTapGesture {
                guard !didDrag else { return }
                onExpand()
            }
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

    private var dragDetectionGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 {
                    didDrag = true
                }
            }
            .onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    didDrag = false
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
    let isSummarizing: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onPreview: () -> Void
    let onReorderChanged: (CGFloat) -> Void
    let onReorderEnded: () -> Void

    @State private var horizontalOffset: CGFloat = 0
    @State private var dragMode: TaskDragMode?
    @State private var isHovering = false

    private var cardColor: Color {
        Color(hex: task.backgroundColorHex)
    }

    private var isDraggingHorizontally: Bool {
        dragMode == .horizontal && abs(horizontalOffset) > 4
    }

    private var displayTitle: String {
        if isSummarizing {
            return "AI 生成中..."
        }

        return splitTitleAndDescription.title
    }

    private var displayDescription: String {
        if let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }

        return splitTitleAndDescription.description
    }

    private var splitTitleAndDescription: (title: String, description: String) {
        let normalized = task.title
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return ("未命名截图任务", "等待视觉模型补全截图里的任务线索。")
        }

        if let structured = structuredTitleAndDescription(from: normalized) {
            return structured
        }

        let compact = normalized
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let separators = CharacterSet(charactersIn: "。！？!?；;，,")
        if let separatorRange = compact.rangeOfCharacter(from: separators) {
            let title = String(compact[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let descriptionStart = compact.index(after: separatorRange.lowerBound)
            let description = String(compact[descriptionStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !title.isEmpty, !description.isEmpty {
                return (title, description)
            }
        }

        if compact.count > 18 {
            let splitIndex = compact.index(compact.startIndex, offsetBy: 18)
            let title = String(compact[..<splitIndex])
            let description = String(compact[splitIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, description.isEmpty ? "查看截图，快速回到这项任务的上下文。" : description)
        }

        return (compact, "查看截图，快速回到这项任务的上下文。")
    }

    private func structuredTitleAndDescription(from text: String) -> (title: String, description: String)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var title: String?
        var description: String?

        for line in lines {
            if let value = value(afterAnyPrefix: ["主标题：", "主标题:", "标题：", "标题:"], in: line) {
                title = value
            } else if let value = value(afterAnyPrefix: ["副标题：", "副标题:", "背景：", "背景:"], in: line) {
                description = value
            }
        }

        guard let title, !title.isEmpty else {
            return nil
        }

        return (title, description?.isEmpty == false ? description! : "查看截图，快速回到这项任务的上下文。")
    }

    private func value(afterAnyPrefix prefixes: [String], in line: String) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    var body: some View {
        ZStack {
            swipeActions

            cardContent
                .offset(x: horizontalOffset)
                .shadow(
                    color: Color.black.opacity(dragMode == nil ? (task.isDone ? 0.025 : 0.07) : 0.14),
                    radius: dragMode == nil ? 8 : 16,
                    y: dragMode == nil ? 3 : 8
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .gesture(rowDragGesture)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: onToggle) {
                Label(task.isDone ? "标记为未完成" : "完成任务", systemImage: "checkmark.circle")
            }

            Button(role: .destructive, action: onDelete) {
                Label("删除任务", systemImage: "trash")
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: 14) {
            leadingVisual

            VStack(alignment: .leading, spacing: 7) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)

                Text(displayDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                SourceBadge(source: task.inputSource)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DragGrip()
                .opacity(dragMode == .vertical || isHovering ? 0.62 : 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 70)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardColor.opacity(task.isDone ? 0.18 : 0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(cardColor.opacity(0.72), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .opacity(task.isDone ? 0.68 : 1)
    }

    private var swipeActions: some View {
        HStack(spacing: 8) {
            ActionRevealView(
                systemName: "checkmark",
                tint: Color(red: 0.47, green: 0.74, blue: 0.55),
                alignment: .leading
            )
            .opacity(isDraggingHorizontally ? 1 : 0)

            Spacer(minLength: 12)

            ActionRevealView(
                systemName: "trash",
                tint: Color(red: 0.9, green: 0.46, blue: 0.42),
                alignment: .trailing
            )
            .opacity(isDraggingHorizontally ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.14), value: isDraggingHorizontally)
    }

    private var rowDragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                if dragMode == nil {
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                    dragMode = isHorizontal ? .horizontal : .vertical
                }

                switch dragMode {
                case .horizontal:
                    horizontalOffset = min(max(value.translation.width, -92), 92)
                case .vertical:
                    horizontalOffset = 0
                    onReorderChanged(value.translation.height)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                switch dragMode {
                case .horizontal:
                    completeHorizontalDrag()
                case .vertical:
                    onReorderEnded()
                case nil:
                    break
                }

                dragMode = nil
            }
    }

    private func completeHorizontalDrag() {
        let offset = horizontalOffset

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            horizontalOffset = 0
        }

        if offset > 72 {
            onToggle()
        } else if offset < -72 {
            onDelete()
        }
    }

    private var leadingVisual: some View {
        Group {
            switch task.inputSource {
            case .screenshot:
                thumbnail
            case .manual:
                manualIconTile
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = task.imageData, let image = NSImage(data: data) {
            Button(action: onPreview) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipped()
                        .opacity(task.isDone ? 0.5 : 1)

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 12, height: 12)
                        .background(Color.black.opacity(0.38))
                        .clipShape(Circle())
                        .padding(4)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("点击查看大图")
            .accessibilityLabel("查看截图大图")
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                }
        }
    }

    private var manualIconTile: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.76))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: task.manualIconName ?? TaskItem.randomManualIconName())
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(cardColor.opacity(0.95))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct SourceBadge: View {
    let source: TaskInputSource

    var body: some View {
        Text(source.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
    }
}

private enum TaskDragMode {
    case horizontal
    case vertical
}

private struct ActionRevealView: View {
    let systemName: String
    let tint: Color
    let alignment: Alignment

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.2))
            .frame(width: 78)
            .overlay(alignment: alignment) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.74))
                    .clipShape(Circle())
                    .padding(.horizontal, 16)
            }
    }
}

private struct DragGrip: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle()
                        .frame(width: 3, height: 3)
                    Circle()
                        .frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(Color.secondary)
        .frame(width: 18, height: 38)
    }
}

private struct ReorderInsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Color.accentColor.opacity(0.58))
                .frame(height: 2)

            Circle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 14)
        .frame(height: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }

                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct ManualTaskFormView: View {
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @FocusState private var isTitleFocused: Bool

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("新建任务")
                    .font(.system(size: 24, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务名称")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("例如：明天确认上线计划", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务描述")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $description)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 118)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
            }

            HStack(spacing: 12) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("创建任务") {
                    onCreate(title, description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            isTitleFocused = true
        }
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

            if let data = task.imageData, let image = NSImage(data: data) {
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
