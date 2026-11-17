import SwiftUI

struct TransferView: View {

    @EnvironmentObject private var store: TransferStore

    @State private var kind: TransferTask.Kind = .upload

    /// 清空全部任务的确认
    @State private var showClearConfirm = false

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
            // 传输任务都是本机数据，下拉只重绘，不请求网络、不弹任何提示
            .refreshable {
                await MainActor.run { store.objectWillChange.send() }
            }
        }
        .background(MD3.background.ignoresSafeArea())
        // 清空全部：系统居中弹窗；确认后给小提示反馈
        .alert("全部删除", isPresented: $showClearConfirm) {
            Button("全部删除", role: .destructive) {
                store.deleteAll()
                ToastCentre.shared.show("已删除全部传输任务记录")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除全部传输记录？此操作不可恢复。")
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
            // 顺序：删除、刷新（暂停功能已去掉，改由点任务本身暂停）
            HStack(spacing: 0) {
                transferIconButton(icon: "trash") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

    /// 与刷新图标同款风格的传输页图标按钮：16pt / 品牌绿 / 34×34 热区
    private func transferIconButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MD3.primary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: TransferTask) -> some View {
        Button {
            // 点任务本身：切换该任务的暂停/恢复，真实作用于底层传输
            store.togglePause(id: task.id)
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
