import AppKit
import SwiftUI

struct ArchiveWindowView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTaskID: TaskItem.ID?

    @State private var previewImageTask: TaskItem?
    @State private var taskPendingDeletion: TaskItem?

    private let createdAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private var archivedTasks: [TaskItem] {
        store.archivedTasks
    }

    private var selectedTask: TaskItem? {
        guard let selectedTaskID else {
            return archivedTasks.first
        }

        return archivedTasks.first { $0.id == selectedTaskID } ?? archivedTasks.first
    }

    var body: some View {
        Group {
            if archivedTasks.isEmpty {
                emptyWindow
            } else {
                splitContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedTaskID == nil || archivedTasks.first(where: { $0.id == selectedTaskID }) == nil {
                selectedTaskID = archivedTasks.first?.id
            }
        }
        .onChange(of: archivedTasks.map(\.id)) { _, newIDs in
            if let current = selectedTaskID, !newIDs.contains(current) {
                selectedTaskID = newIDs.first
            } else if selectedTaskID == nil {
                selectedTaskID = newIDs.first
            }
        }
        .sheet(item: $previewImageTask) { task in
            ArchiveImagePreviewView(task: task)
        }
        .alert(item: $taskPendingDeletion) { task in
            Alert(
                title: Text("永久删除此任务？"),
                message: Text("此操作无法撤销，任务及其所有内容将被永久移除。"),
                primaryButton: .destructive(Text("删除")) {
                    store.permanentlyDelete(task)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var splitContent: some View {
        HStack(spacing: 0) {
            archiveSidebar

            Divider()

            detailPane
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var archiveSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("归档任务")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(archivedTasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text("点击查看详情和笔记。需要让任务回到列表时，使用右侧的「撤销归档」。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(archivedTasks) { task in
                        ArchiveTaskListItem(
                            task: task,
                            isSelected: task.id == selectedTask?.id,
                            createdAtText: createdAtFormatter.string(from: task.createdAt)
                        ) {
                            selectedTaskID = task.id
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .padding(18)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let task = selectedTask {
            VStack(spacing: 0) {
                detailTitleBar(for: task)

                Divider()

                detailContent(for: task)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            emptyWindow
        }
    }

    private func detailTitleBar(for task: TaskItem) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(TaskDisplayText(task: task).title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text("归档于 \(createdAtFormatter.string(from: task.createdAt)) · \(task.inputSource.label)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.unarchive(task)
            } label: {
                Label("撤销归档", systemImage: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("将任务恢复为进行中并放回任务列表")

            Button(role: .destructive) {
                taskPendingDeletion = task
            } label: {
                Label("永久删除", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("从归档中永久删除此任务，无法恢复")
        }
        .padding(.horizontal, 28)
        .frame(height: 64)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private func detailContent(for task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailSummary(for: task)

                if task.imageData != nil {
                    screenshotSection(for: task)
                }

                noteSection(for: task)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func detailSummary(for task: TaskItem) -> some View {
        let displayText = TaskDisplayText(task: task)

        return VStack(alignment: .leading, spacing: 8) {
            Text("任务描述")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(displayText.description)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func screenshotSection(for task: TaskItem) -> some View {
        if let data = task.imageData, let image = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 8) {
                Text("截图")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button {
                    previewImageTask = task
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .center)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("点击查看大图")
            }
        }
    }

    private func noteSection(for task: TaskItem) -> some View {
        let firstNote = task.notes.first
        let markdown = firstNote.flatMap { try? store.readNoteMarkdown($0) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            Text(task.notes.count > 1 ? "任务笔记（\(task.notes.count) 篇，预览第一篇）" : "任务笔记")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if firstNote == nil {
                Text("这项任务没有保存笔记。")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
            } else if markdown.isEmpty {
                Text("第一篇笔记为空，或文件暂时无法读取。")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
            } else {
                MarkdownPreviewView(markdown: markdown, isOutlineVisible: false)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
            }
        }
    }

    private var emptyWindow: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text("暂时没有归档任务")
                .font(.title3.weight(.semibold))

            Text("拖动任务卡片到底部投放区的「归档」目标，即可把它移到归档。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct ArchiveTaskListItem: View {
    let task: TaskItem
    let isSelected: Bool
    let createdAtText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                leadingVisual

                VStack(alignment: .leading, spacing: 6) {
                    Text(TaskDisplayText(task: task).title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("创建于 \(createdAtText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(hex: task.backgroundColorHex).opacity(0.36) : Color.white.opacity(0.62))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.black.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    @ViewBuilder
    private var leadingVisual: some View {
        switch task.inputSource {
        case .screenshot:
            if let data = task.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
            } else {
                placeholderTile(systemName: "photo")
            }
        case .manual:
            placeholderTile(systemName: task.manualIconName ?? "square.and.pencil")
        }
    }

    private func placeholderTile(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.86))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            }
    }
}

private struct ArchiveImagePreviewView: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(TaskDisplayText(task: task).title)
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
