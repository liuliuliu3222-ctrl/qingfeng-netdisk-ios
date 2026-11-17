import SwiftUI

struct TransferView: View {

    @EnvironmentObject private var store: TransferStore

    @State private var kind: TransferTask.Kind = .upload

    /// 删除单个任务的确认目标（长按任务行触发）
    @State private var deleteTarget: TransferTask?
    @State private var showDeleteConfirm = false
    /// 清空全部任务的确认
    @State private var showClearConfirm = false

    private var visibleTasks: [TransferTask] { store.items(kind: kind) }

    /// 是否还有进行中的任务，决定暂停按钮显示「暂停」还是「继续」
    private var hasRunning: Bool { store.runningCount() > 0 }

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
                                    .contentShape(Rectangle())
                                    // 长按任务本身弹系统居中删除确认，与文件页观感一致
                                    .highPriorityGesture(
                                        LongPressGesture(minimumDuration: 0.5)
                                            .onEnded { _ in
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                deleteTarget = task
                                                showDeleteConfirm = true
                                            }
                                    )
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
            // 传输任务都是本机数据，下拉只重绘，不请求网络、不弹任何提示
            .refreshable {
                await MainActor.run { store.objectWillChange.send() }
            }
        }
        .background(MD3.background.ignoresSafeArea())
        // 暂停 / 继续 / 清空全部：系统居中弹窗，与全局删除风格一致
        .alert("清空传输列表", isPresented: $showClearConfirm) {
            Button("全部删除", role: .destructive) { store.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除全部传输记录及其已下载的本地文件？此操作不可恢复。")
        }
        // 长按单个任务：系统居中弹窗确认是否删除该任务
        .alert("删除任务", isPresented: $showDeleteConfirm, presenting: deleteTarget) { task in
            Button("删除", role: .destructive) { store.delete(id: task.id) }
            Button("取消", role: .cancel) {}
        } message: { task in
            Text("确定删除任务「\(task.name)」及其本地文件？")
        }
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
            Spacer(minLength: 4)
            // 顺序：暂停、删除、刷新
            HStack(spacing: 0) {
                // 暂停 / 继续：有进行中任务则暂停，否则恢复已暂停任务
                MDIconButton(icon: hasRunning ? "pause.fill" : "play.fill", size: 17) {
                    if hasRunning {
                        store.pauseAll()
                    } else {
                        store.resumeAll()
                    }
                }
                // 删除：删除全部（本地文件 + 列表记录），带居中确认
                MDIconButton(icon: "trash", tint: MD3.error, size: 18) {
                    showClearConfirm = true
                }
                SpinningRefreshIcon(tint: MD3.primary, size: 16, hitSize: 34) {
                    store.objectWillChange.send()
                }
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
