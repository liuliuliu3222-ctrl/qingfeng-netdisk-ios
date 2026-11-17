import SwiftUI

/// 回收站页面内的轻量提示。
/// TrashView 以 sheet 呈现，UIKit 呈现层级高于挂在 RootView 上的全局 ToastOverlay，
/// 会把全局 Toast 盖住 —— 提示因此要等 sheet 关掉才在上级主页冒出来。
/// 这里改用页面内的提示层，保证还原/删除/清空的反馈就停留在当前回收站页面底部，
/// 样式与全局 MDToast 完全一致（品牌绿），不再抛到上级主页。
private final class TrashToast: ObservableObject {
    @Published private(set) var message: String?
    private var stamp = 0

    func show(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            self.stamp += 1
            let current = self.stamp
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if self.stamp == current { self.message = nil }
            }
        }
    }
}

struct TrashView: View {

    @Environment(\.dismiss) private var dismiss

    @StateObject private var toast = TrashToast()

    @State private var items: [QFFile] = []

    @State private var purgeTarget: QFFile?
    @State private var showPurgeConfirm = false
    @State private var showEmptyConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(
                title: "回收站",
                subtitle: items.isEmpty ? "回收站是空的" : "共 \(items.count) 项，彻底删除后释放空间",
                showsBack: true,
                onBack: { dismiss() },
                trailing: AnyView(
                    HStack(spacing: 0) {
                        SpinningRefreshIcon {
                            _ = Task { await load() }
                        }
                        MDIconButton(icon: "trash.slash", tint: MD3.error) {
                            // 点击垃圾桶图标立即给出触感反馈，再弹居中确认
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showEmptyConfirm = true
                        }
                    }
                )
            )

            ScrollView {
                VStack(spacing: 12) {
                    // 空状态只取决于 items 是否为空，不再受加载态影响。
                    // 刷新时后台静默更新数据，页面结构保持稳定，不重绘、不闪屏。
                    if items.isEmpty {
                        MDEmptyState(icon: "trash",
                                     title: "回收站是空的",
                                     detail: "删除的文件会先进入这里")
                            .frame(minHeight: 360)
                    } else {
                        MDCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, file in
                                    FileRow(file: file, showsChevron: false)
                                        .contextMenu {
                                            Button {
                                                restore(file)
                                            } label: {
                                                Label("还原", systemImage: "arrow.uturn.left")
                                            }
                                            Button(role: .destructive) {
                                                purgeTarget = file
                                                showPurgeConfirm = true
                                            } label: {
                                                Label("彻底删除", systemImage: "trash")
                                            }
                                        }
                                    if index < items.count - 1 {
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
            .refreshable { await load() }
        }
        .background(MD3.background.ignoresSafeArea())
        // 页面内提示层：固定在本页底部，不会被 sheet 层级遮住，也不会抛到上级主页。
        .overlay(alignment: .bottom) {
            if let message = toast.message {
                MDToast(message: message)
                    .padding(.bottom, 48)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.message)
        .task { await load() }
        // 彻底删除确认：系统原生居中弹窗（与设置页退出登录一致），文案/按钮不变
        .alert("彻底删除", isPresented: $showPurgeConfirm) {
            Button("删除", role: .destructive) { performPurge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定彻底删除「\(purgeTarget?.name ?? "")」？删除后不可恢复，空间将释放。")
        }
        .alert("清空回收站", isPresented: $showEmptyConfirm) {
            Button("全部删除", role: .destructive) { emptyTrash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定彻底删除回收站内全部 \(items.count) 项？删除后不可恢复。")
        }
    }

    private func load() async {
        // 后台静默更新：不切换任何加载态，页面结构不重绘、不闪屏。
        do {
            let list = try await ApiClient.shared.trashList()
            // 数据无变化时不重新赋值，避免任何隐式重绘导致的闪屏
            if items != list { items = list }
        } catch {
            // 刷新失败或被取消：保留现有列表，不清空、不弹提示
        }
    }

    private func restore(_ file: QFFile) {
        Task {
            do {
                try await ApiClient.shared.trashRestore(ids: [file.id])
                toast.show("已还原")
                await load()
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }

    private func performPurge() {
        guard let target = purgeTarget else { return }
        Task {
            do {
                try await ApiClient.shared.trashPurge(ids: [target.id])
                toast.show("已彻底删除")
                await load()
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }

    private func emptyTrash() {
        guard !items.isEmpty else {
            toast.show("回收站已经是空的")
            return
        }
        Task {
            do {
                try await ApiClient.shared.trashEmpty()
                toast.show("回收站已清空")
                await load()
            } catch {
                toast.show(error.localizedDescription)
            }
        }
    }
}
