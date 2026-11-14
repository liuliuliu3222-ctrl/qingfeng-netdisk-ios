import SwiftUI

struct TransferView: View {

    @EnvironmentObject private var store: TransferStore

    @State private var kind: TransferTask.Kind = .upload

    private var visibleTasks: [TransferTask] { store.items(kind: kind) }

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "传输",
                       subtitle: store.runningCount() > 0 ? "\(store.runningCount()) 个进行中" : "暂无进行中的任务")

            segmented

            ScrollView {
                VStack(spacing: 12) {
                    if visibleTasks.isEmpty {
                        MDEmptyState(icon: kind == .upload ? "arrow.up.circle" : "arrow.down.circle",
                                     title: kind == .upload ? "暂无上传任务" : "暂无下载任务",
                                     detail: kind == .upload ? "在「文件」页点右下角 + 上传文件" : "预览文件时点「下载」")
                            .frame(minHeight: 360)
                    } else {
                        MDCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                                    taskRow(task)
                                    if index < visibleTasks.count - 1 {
                                        Divider()
                                            .overlay(MD3.outlineVariant)
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(MD3.background.ignoresSafeArea())
    }

    private var segmented: some View {
        HStack(spacing: 8) {
            ForEach([TransferTask.Kind.upload, TransferTask.Kind.download], id: \.rawValue) { item in
                Button {
                    kind = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 13, weight: .medium))
                        Text("\(item.title)\(store.items(kind: item).isEmpty ? "" : " \(store.items(kind: item).count)")")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(kind == item ? MD3.onPrimaryContainer : MD3.onSurfaceVariant)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(kind == item ? MD3.primaryContainer : MD3.surfaceContainerHigh)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                store.objectWillChange.send()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MD3.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func taskRow(_ task: TransferTask) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(task.state == .failed ? MD3.errorContainer : MD3.primaryContainer)
                    .frame(width: 42, height: 42)
                Image(systemName: task.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(task.state == .failed ? MD3.error : MD3.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(task.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MD3.onSurface)
                    .lineLimit(1)
                ProgressView(value: Double(task.percent), total: 100)
                    .tint(task.state == .failed ? MD3.error : MD3.primary)
                Text(task.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(task.state == .failed ? MD3.error : MD3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
