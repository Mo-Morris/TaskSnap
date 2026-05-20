import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskBoardView: View {
    @ObservedObject var store: TaskStore
    @State private var isDropTargeted = false

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

            Text("它会变成一条可划掉的任务")
                .font(.callout)
                .foregroundStyle(.secondary)
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
                    }
                }
            }
            .padding(12)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        store.addImageData(data)
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
                        store.addImageData(imageData, title: url.deletingPathExtension().lastPathComponent)
                    }
                }
                return true
            }
        }

        return false
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help(task.isDone ? "标记为未完成" : "划掉任务")

            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                if let image = NSImage(data: task.imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 112)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(task.isDone ? 0.45 : 1)
                }
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除任务")
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
