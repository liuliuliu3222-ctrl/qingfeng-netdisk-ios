import UIKit
import SwiftUI

struct CategoryTarget: Identifiable {
    let id = UUID()
    let title: String
    let type: String
}

struct HomeView: View {

    @EnvironmentObject private var session: SessionStore
    var switchToFiles: () -> Void

    @State private var recents: [QFFile] = []
    @State private var loadingRecents = false
    @State private var categoryTarget: CategoryTarget?
    @State private var previewTarget: QFFile?
    @State private var showTrash = false
    @State private var showBrowser = false
    @State private var showMember = false

    private let categories: [(String, String, String)] = [
        ("图片", "image", "photo.on.rectangle"),
        ("视频", "video", "play.rectangle"),
        ("文档", "doc", "doc.text"),
        ("音频", "audio", "waveform"),
        ("压缩包", "zip", "doc.zipper")
    ]

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(
                title: "清风网盘",
                subtitle: session.me.tierName,
                trailing: AnyView(
                    HStack(spacing: 0) {
                        MDIconButton(icon: "magnifyingglass") { switchToFiles() }
                        MDIconButton(icon: "arrow.clockwise") {
                            Task { await refresh() }
                        }
                    }
                )
            )

            ScrollView {
                VStack(spacing: 14) {
                    storageCard
                    categoryGrid
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await refresh() }
        }
        .background(MD3.background.ignoresSafeArea())
        .task { await refresh() }
        .sheet(item: $categoryTarget) { target in
            CategoryView(title: target.title, type: target.type)
                .environmentObject(session)
        }
        .sheet(item: $previewTarget) { file in
            PreviewView(file: file)
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .sheet(isPresented: $showBrowser) {
            BrowserView()
        }
        .sheet(isPresented: $showMember) {
            MemberSheet()
                .environmentObject(session)
        }
    }

    // MARK: 存储卡片

    private var storageCard: some View {
        MDCard(radius: MD3.radiusExtraLarge, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(MD3.primary)
                    Text("存储空间")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MD3.onSurface)
                    Spacer()
                    Text(session.me.tierName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MD3.onPrimaryContainer)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(MD3.primaryContainer)
                        .clipShape(Capsule())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MD3.surfaceContainerHighest)
                        Capsule()
                            .fill(MD3.primary)
                            .frame(width: max(4, proxy.size.width * session.me.fraction))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(ByteText.string(session.me.usedBytes)) / \(ByteText.string(session.me.quotaBytes))")
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant)
                    Spacer()
                    Button {
                        showMember = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("已使用 \(session.me.percent)%")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(MD3.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 分类宫格

    private var categoryGrid: some View {
        MDCard(padding: 14) {
            HStack(spacing: 0) {
                ForEach(categories, id: \.1) { item in
                    Button {
                        categoryTarget = CategoryTarget(title: item.0, type: item.1)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(MD3.primaryContainer)
                                    .frame(width: 46, height: 46)
                                Image(systemName: item.2)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(MD3.primary)
                            }
                            Text(item.0)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MD3.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 快捷入口

    private var quickEntries: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                MDRow(icon: "trash", title: "回收站", subtitle: "还原或彻底删除已删文件") {
                    showTrash = true
                }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "globe", title: "网页浏览", subtitle: "在内置浏览器中打开网页版") {
                    showBrowser = true
                }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "crown", title: "会员中心", subtitle: "查看等级与空间配额") {
                    showMember = true
                }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "magnifyingglass", title: "全部文件", subtitle: "浏览、搜索与上传") {
                    switchToFiles()
                }
            }
        }
    }

    // MARK: 最近文件

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近使用")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MD3.onSurface)
                Spacer()
                if loadingRecents {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 4)

            if recents.isEmpty {
                MDCard(padding: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.6))
                        Text(loadingRecents ? "正在加载…" : "暂无最近记录")
                            .font(.system(size: 13))
                            .foregroundStyle(MD3.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                MDCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(recents.prefix(5).enumerated()), id: \.element.id) { index, file in
                            Button {
                                previewTarget = file
                            } label: {
                                FileRow(file: file, showsChevron: false)
                            }
                            .buttonStyle(.plain)
                            if index < min(recents.count, 5) - 1 {
                                Divider().overlay(MD3.outlineVariant).padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
    }

    private func refresh() async {
        loadingRecents = true
        await session.refreshProfile()
        do {
            // 每次都重新向服务端取，保证上传新文件后刷新能拿到最新记录
            recents = try await ApiClient.shared.recent()
        } catch {
            // 刷新失败或被取消：保留已有列表，不清空、也不弹任何提示
        }
        loadingRecents = false
    }
}
