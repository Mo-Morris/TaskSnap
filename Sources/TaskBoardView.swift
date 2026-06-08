import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskBoardView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var pasteCommandDispatcher: PasteCommandDispatcher
    @EnvironmentObject private var shellState: AppShellState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @State private var previewTask: TaskItem?
    @State private var editingTask: TaskItem?
    @State private var inputAlert: InputAlert?
    @State private var isShowingManualTaskForm = false
    @State private var draggingTaskID: TaskItem.ID?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartRowFrame: CGRect?
    @State private var reorderTargetIndex: Int?
    @State private var hoveredDropZone: DropZone?
    @State private var rowFrames: [TaskItem.ID: CGRect] = [:]
    @State private var dropZoneFrames: [DropZone: CGRect] = [:]
    @FocusState private var isPasteTargetFocused: Bool

    private let taskListSpaceName = "taskListSpace"
    private let reorderAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        Group {
            if shellState.isMainWindowCollapsed {
                CollapsedTaskIconView(
                    activeTaskCount: activeTaskCount,
                    isWorking: !store.summarizingTaskIDs.isEmpty
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        shellState.isMainWindowCollapsed = false
                    }
                }
            } else {
                expandedBoard
            }
        }
        .overlay {
            if !shellState.isMainWindowCollapsed || isDropTargeted {
                RoundedRectangle(cornerRadius: shellState.isMainWindowCollapsed ? 36 : 14)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color.white.opacity(0.18),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: shellState.isMainWindowCollapsed ? 36 : 14, style: .continuous))
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
        .onChange(of: shellState.manualTaskFormRequestID) { _, newValue in
            guard newValue > 0 else { return }
            if shellState.isMainWindowCollapsed {
                shellState.isMainWindowCollapsed = false
            }
            isShowingManualTaskForm = true
        }
        .sheet(item: $previewTask) { task in
            ImagePreviewView(task: task)
        }
        .sheet(isPresented: $isShowingManualTaskForm) {
            ManualTaskFormView { title, description in
                store.addManualTask(title: title, description: description)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditFormView(task: task) { title, description in
                store.updateTask(task, title: title, description: description)
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
        store.activeTaskCount
    }

    private var visibleTasks: [TaskItem] {
        store.visibleTasks
    }

    private var expandedBoard: some View {
        VStack(spacing: 0) {
            titleBar

            if visibleTasks.isEmpty {
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
        GeometryReader { containerProxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(
                                task: task,
                                isPickedUp: draggingTaskID == task.id,
                                isSummarizing: store.summarizingTaskIDs.contains(task.id),
                                coordinateSpaceName: taskListSpaceName
                            ) {
                                withAnimation(reorderAnimation) {
                                    store.archive(task)
                                }
                            } onToggleComplete: {
                                withAnimation(reorderAnimation) {
                                    store.toggleCompletion(task)
                                }
                            } onComplete: {
                                withAnimation(reorderAnimation) {
                                    store.complete(task)
                                }
                            } onRestore: {
                                withAnimation(reorderAnimation) {
                                    store.restore(task)
                                }
                            } onPreview: {
                                previewTask = task
                            } onEdit: {
                                editingTask = task
                            } onOpenNote: {
                                shellState.selectedNoteTaskID = task.id
                                openWindow(id: "task-note")
                            } onDragChanged: { translation, location in
                                updateDragState(
                                    for: task,
                                    sourceIndex: index,
                                    translation: translation,
                                    location: location
                                )
                            } onDragEnded: {
                                finishDrag(for: task)
                            }
                            .offset(
                                x: draggingTaskID == task.id ? dragOffset.width : 0,
                                y: draggingTaskID == task.id ? dragOffset.height : 0
                            )
                            .zIndex(draggingTaskID == task.id ? 10 : 0)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: RowFramePreferenceKey.self,
                                        value: [task.id: proxy.frame(in: .named(taskListSpaceName))]
                                    )
                                }
                            )
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
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        insertionIndicatorOverlay
                    }
                    .onPreferenceChange(RowFramePreferenceKey.self) { newFrames in
                        rowFrames = newFrames
                    }
                }

                dropZoneBar
                    .position(dropZoneBarCenter(in: containerProxy.size))
                    .opacity(draggingTaskID != nil ? 1 : 0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: draggingTaskID)
                    .allowsHitTesting(false)
            }
            .coordinateSpace(name: taskListSpaceName)
            .onPreferenceChange(DropZoneFramePreferenceKey.self) { newFrames in
                dropZoneFrames = newFrames
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dropZoneBarCenter(in containerSize: CGSize) -> CGPoint {
        let estimatedHeight: CGFloat = 96
        let estimatedWidth: CGFloat = 232
        let spacing: CGFloat = 14
        let edgeMargin: CGFloat = 14

        guard let rowFrame = dragStartRowFrame else {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height + estimatedHeight)
        }

        let cardCenterX = rowFrame.midX
        let cardTopY = rowFrame.minY
        let cardBottomY = rowFrame.maxY

        let belowCenterY = cardBottomY + spacing + estimatedHeight / 2
        let aboveCenterY = cardTopY - spacing - estimatedHeight / 2
        let bottomLimit = containerSize.height - estimatedHeight / 2 - edgeMargin
        let topLimit = estimatedHeight / 2 + edgeMargin

        let resolvedY: CGFloat
        if belowCenterY <= bottomLimit {
            resolvedY = belowCenterY
        } else if aboveCenterY >= topLimit {
            resolvedY = aboveCenterY
        } else {
            resolvedY = bottomLimit
        }

        let leftLimit = estimatedWidth / 2 + edgeMargin
        let rightLimit = max(leftLimit, containerSize.width - estimatedWidth / 2 - edgeMargin)
        let resolvedX = min(max(cardCenterX, leftLimit), rightLimit)

        return CGPoint(x: resolvedX, y: resolvedY)
    }

    private var dropZoneBar: some View {
        HStack(spacing: 22) {
            DropZoneTarget(
                kind: primaryDropZoneKind,
                isHovered: hoveredDropZone == .toggle
            )
            .background(dropZoneFrameReader(zone: .toggle))

            DropZoneTarget(
                kind: .archive,
                isHovered: hoveredDropZone == .archive
            )
            .background(dropZoneFrameReader(zone: .archive))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.14), radius: 16, y: 5)
        }
        .padding(.bottom, 16)
    }

    private func dropZoneFrameReader(zone: DropZone) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DropZoneFramePreferenceKey.self,
                value: [zone: proxy.frame(in: .named(taskListSpaceName))]
            )
        }
    }

    private var primaryDropZoneKind: DropZoneTargetKind {
        if let id = draggingTaskID,
           let task = visibleTasks.first(where: { $0.id == id }),
           task.status == .completed {
            return .restore
        }
        return .complete
    }

    @ViewBuilder
    private var insertionIndicatorOverlay: some View {
        if let targetIndex = reorderTargetIndex, draggingTaskID != nil {
            ReorderInsertionIndicator()
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .offset(y: insertionLineY(for: targetIndex) - 4)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func insertionLineY(for index: Int) -> CGFloat {
        let tasks = visibleTasks
        guard !tasks.isEmpty else { return 10 }

        if index <= 0 {
            guard let frame = rowFrames[tasks[0].id] else { return 10 }
            return frame.minY - 7
        }

        if index >= tasks.count {
            guard let frame = rowFrames[tasks[tasks.count - 1].id] else { return 10 }
            return frame.maxY + 7
        }

        if let prev = rowFrames[tasks[index - 1].id],
           let next = rowFrames[tasks[index].id] {
            return (prev.maxY + next.minY) / 2
        }

        return 10
    }

    private func updateDragState(
        for task: TaskItem,
        sourceIndex: Int,
        translation: CGSize,
        location: CGPoint
    ) {
        if draggingTaskID != task.id {
            draggingTaskID = task.id
            dragStartRowFrame = rowFrames[task.id]
        }
        dragOffset = translation

        var hovered: DropZone?
        for (zone, frame) in dropZoneFrames where frame.contains(location) {
            hovered = zone
            break
        }

        if hoveredDropZone != hovered {
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredDropZone = hovered
            }
        }

        if hovered == nil {
            let count = visibleTasks.count
            var bestIndex = sourceIndex
            var bestDistance = CGFloat.infinity
            for candidate in 0...count {
                let distance = abs(insertionLineY(for: candidate) - location.y)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = candidate
                }
            }

            if reorderTargetIndex != bestIndex {
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                    reorderTargetIndex = bestIndex
                }
            }
        } else if reorderTargetIndex != nil {
            withAnimation(.easeOut(duration: 0.15)) {
                reorderTargetIndex = nil
            }
        }
    }

    private func finishDrag(for task: TaskItem) {
        if let zone = hoveredDropZone {
            switch zone {
            case .toggle:
                withAnimation(reorderAnimation) {
                    if task.status == .completed {
                        store.restore(task)
                    } else {
                        store.complete(task)
                    }
                }
            case .archive:
                withAnimation(reorderAnimation) {
                    store.archive(task)
                }
            }
        } else if let reorderTargetIndex {
            withAnimation(reorderAnimation) {
                store.move(task, to: reorderTargetIndex)
            }
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            draggingTaskID = nil
            dragOffset = .zero
            dragStartRowFrame = nil
            reorderTargetIndex = nil
            hoveredDropZone = nil
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        if shellState.isMainWindowCollapsed {
            shellState.isMainWindowCollapsed = false
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
            shellState.isMainWindowCollapsed = false
            inputAlert = .missingVisionConfiguration
            return
        }

        if !store.addImageFromPasteboard() {
            shellState.isMainWindowCollapsed = false
            inputAlert = .addFailed("剪贴板里没有可识别的图片。")
        } else if shellState.isMainWindowCollapsed {
            shellState.isMainWindowCollapsed = false
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

struct TaskDisplayText {
    let title: String
    let description: String

    init(task: TaskItem) {
        if let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            let normalizedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = normalizedTitle.isEmpty ? "未命名截图任务" : normalizedTitle
            self.description = description
            return
        }

        let parsed = Self.parseTitleAndDescription(from: task.title)
        title = parsed.title
        description = parsed.description
    }

    private static func parseTitleAndDescription(from text: String) -> (title: String, description: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private static func structuredTitleAndDescription(from text: String) -> (title: String, description: String)? {
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

    private static func value(afterAnyPrefix prefixes: [String], in line: String) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isPickedUp: Bool
    let isSummarizing: Bool
    let coordinateSpaceName: String
    let onArchive: () -> Void
    let onToggleComplete: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onOpenNote: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void

    @State private var isHovering = false

    private var cardColor: Color {
        Color(hex: task.backgroundColorHex)
    }

    private var manualIconColor: Color {
        switch task.backgroundColorHex.uppercased() {
        case "#F8E7E0":
            Color(red: 0.72, green: 0.27, blue: 0.18)
        case "#E8F2D9":
            Color(red: 0.32, green: 0.48, blue: 0.16)
        case "#DDEFF5":
            Color(red: 0.16, green: 0.45, blue: 0.58)
        case "#F7EDCC":
            Color(red: 0.60, green: 0.43, blue: 0.08)
        case "#E9E4F7":
            Color(red: 0.43, green: 0.32, blue: 0.68)
        case "#DDF1EA":
            Color(red: 0.16, green: 0.48, blue: 0.39)
        case "#F5E0EC":
            Color(red: 0.64, green: 0.25, blue: 0.47)
        case "#E6EDF9":
            Color(red: 0.23, green: 0.39, blue: 0.68)
        default:
            Color(nsColor: .labelColor).opacity(0.78)
        }
    }

    private var displayTitle: String {
        if isSummarizing {
            return "AI 生成中..."
        }

        return TaskDisplayText(task: task).title
    }

    private var displayDescription: String {
        TaskDisplayText(task: task).description
    }

    private var isCompleted: Bool {
        task.status == .completed
    }

    var body: some View {
        cardContent
            .scaleEffect(isPickedUp ? 1.04 : 1)
            .shadow(
                color: Color.black.opacity(isPickedUp ? 0.22 : (isCompleted ? 0.025 : 0.07)),
                radius: isPickedUp ? 18 : 8,
                y: isPickedUp ? 10 : 3
            )
            .opacity(isPickedUp ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isPickedUp)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .gesture(rowDragGesture)
            .onHover { hovering in
                guard !isPickedUp else { return }
                isHovering = hovering
            }
            .contextMenu {
                if isCompleted {
                    Button(action: onRestore) {
                        Label("恢复进行中", systemImage: "arrow.uturn.backward.circle")
                    }
                } else {
                    Button(action: onComplete) {
                        Label("标记完成", systemImage: "checkmark.circle")
                    }
                }

                Button(action: onArchive) {
                    Label("归档任务", systemImage: "archivebox")
                }

                Button(action: onEdit) {
                    Label("编辑任务", systemImage: "pencil")
                }
            }
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: 14) {
            leadingVisual

            VStack(alignment: .leading, spacing: 7) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)

                Text(displayDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough(isCompleted)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                SourceBadge(source: task.inputSource, isCompleted: isCompleted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isPickedUp else { return }
                onOpenNote()
            }

            DragGrip()
                .opacity(isPickedUp || isHovering ? 0.62 : 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 70)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(cardColor.opacity(isCompleted ? 0.18 : 0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(cardColor.opacity(0.72), lineWidth: 1.2)
                .allowsHitTesting(false)
        }
        .opacity(isCompleted ? 0.68 : 1)
    }

    private var rowDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if isHovering {
                    isHovering = false
                }
                onDragChanged(value.translation, value.location)
            }
            .onEnded { _ in
                onDragEnded()
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
                        .opacity(isCompleted ? 0.5 : 1)

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
            .fill(Color.white.opacity(0.9))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: task.manualIconName ?? TaskItem.randomManualIconName())
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(manualIconColor.opacity(isCompleted ? 0.62 : 1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct SourceBadge: View {
    let source: TaskInputSource
    let isCompleted: Bool

    var body: some View {
        Text(source.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .strikethrough(isCompleted)
    }
}

private enum DropZone: Hashable {
    case toggle
    case archive
}

private enum DropZoneTargetKind {
    case complete
    case restore
    case archive

    var iconName: String {
        switch self {
        case .complete: "checkmark"
        case .restore: "arrow.uturn.backward"
        case .archive: "archivebox"
        }
    }

    var label: String {
        switch self {
        case .complete: "完成"
        case .restore: "恢复进行中"
        case .archive: "归档"
        }
    }

    var tint: Color {
        switch self {
        case .complete: Color(red: 0.32, green: 0.66, blue: 0.42)
        case .restore: Color(red: 0.42, green: 0.55, blue: 0.85)
        case .archive: Color(red: 0.58, green: 0.45, blue: 0.78)
        }
    }
}

private struct DropZoneTarget: View {
    let kind: DropZoneTargetKind
    let isHovered: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(kind.tint.opacity(isHovered ? 0.32 : 0.14))

                Image(systemName: kind.iconName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(kind.tint)
                    .scaleEffect(isHovered ? 1.1 : 1)
            }
            .frame(width: 56, height: 56)
            .overlay {
                Circle()
                    .stroke(kind.tint.opacity(isHovered ? 0.55 : 0.18), lineWidth: isHovered ? 1.8 : 1)
            }
            .scaleEffect(isHovered ? 1.12 : 1)
            .shadow(
                color: kind.tint.opacity(isHovered ? 0.32 : 0),
                radius: isHovered ? 12 : 0,
                y: isHovered ? 5 : 0
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isHovered)

            Text(kind.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind.tint.opacity(isHovered ? 1.0 : 0.8))
                .lineLimit(1)
        }
        .frame(width: 86)
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

struct PointingHandCursorModifier: ViewModifier {
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

extension View {
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

private struct TaskEditFormView: View {
    let task: TaskItem
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, onSave: @escaping (String, String) -> Void) {
        self.task = task
        self.onSave = onSave

        let displayText = TaskDisplayText(task: task)
        _title = State(initialValue: displayText.title)
        _description = State(initialValue: displayText.description)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("编辑任务")
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

                Button("保存修改") {
                    onSave(title, description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
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
    @AppStorage(AppTheme.storageKey) private var themeRawValue = AppTheme.light.rawValue

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

            SettingsThemeRow(themeRawValue: $themeRawValue)

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

private struct SettingsThemeRow: View {
    @Binding var themeRawValue: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.title3)
                .foregroundStyle(SettingsPalette.accent)
                .frame(width: 36, height: 36)
                .background(SettingsPalette.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("主题")
                    .font(.body.weight(.medium))
                    .foregroundStyle(SettingsPalette.primaryText)

                Text("切换 TaskSnap 的浅色或深色外观。")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
            }

            Spacer(minLength: 16)

            Picker("主题", selection: $themeRawValue) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.localizedTitle).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 156)
        }
        .padding(.vertical, 20)
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

private struct RowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TaskItem.ID: CGRect] = [:]

    static func reduce(value: inout [TaskItem.ID: CGRect], nextValue: () -> [TaskItem.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DropZoneFramePreferenceKey: PreferenceKey {
    static let defaultValue: [DropZone: CGRect] = [:]

    static func reduce(value: inout [DropZone: CGRect], nextValue: () -> [DropZone: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension Color {
    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(normalized, radix: 16) ?? 0xF8E7E0
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
