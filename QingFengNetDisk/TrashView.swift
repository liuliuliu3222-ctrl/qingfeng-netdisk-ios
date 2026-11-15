import SwiftUI

struct TrashView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var items: [QFFile] = []
    @State private var loading = false

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
                        MDIconButton(icon: "arrow.clockwise") {
                            Task { await load() }
                        }
                        MDIconButton(icon: "trash.slash", tint: MD3.error) {
                            showEmptyConfirm = true
                        }
                    }
                )
            )

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty && !loading {
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
        .task { await load() }
        .confirmationDialog("彻底删除", isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { performPurge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定彻底删除「\(purgeTarget?.name ?? "")」？删除后不可恢复，空间将释放。")
        }
        .confirmationDialog("清空回收站", isPresented: $showEmptyConfirm, titleVisibility: .visible) {
            Button("全部删除", role: .destructive) { emptyTrash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定彻底删除回收站内全部 \(items.count) 项？删除后不可恢复。")
        }
    }

    private func load() async {
        loading = true
        do {
            items = try await ApiClient.shared.trashList()
        } catch {
            // 刷新失败或被取消：保留现有列表，不清空、不弹提示
        }
        loading = false
    }

    private func restore(_ file: QFFile) {
        Task {
            do {
                try await ApiClient.shared.trashRestore(ids: [file.id])
                ToastCentre.shared.show("已还原")
                await load()
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func performPurge() {
        guard let target = purgeTarget else { return }
        Task {
            do {
                try await ApiClient.shared.trashPurge(ids: [target.id])
                ToastCentre.shared.show("已彻底删除")
                await load()
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }

    private func emptyTrash() {
        guard !items.isEmpty else {
            ToastCentre.shared.show("回收站已经是空的")
            return
        }
        Task {
            do {
                try await ApiClient.shared.trashEmpty()
                ToastCentre.shared.show("回收站已清空")
                await load()
            } catch {
                ToastCentre.shared.show(error.localizedDescription)
            }
        }
    }
}
