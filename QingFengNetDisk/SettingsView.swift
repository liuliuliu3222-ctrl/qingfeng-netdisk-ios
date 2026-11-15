import UIKit
import SwiftUI

/// 设置页内的轻量提示。
/// 全局 ToastOverlay 挂在 RootView 上，而本页是 sheet（UIKit 呈现层级更高），
/// 会把全局 Toast 完全盖住 —— 提示因此要等 sheet 关掉才在「我的」页、
/// 甚至退出后的登录页冒出来。这里改用页面内的提示层，保证清空缓存等操作
/// 就在当前设置页即时给出反馈。
private final class SettingsToast: ObservableObject {
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

struct SettingsView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var toast = SettingsToast()

    @State private var server = AppSettings.server
    @State private var sharecode = AppSettings.sharecode
    @State private var chunkSizeMB = AppSettings.chunkSizeMB
    @State private var showChunkSizePicker = false
    @State private var status = ""
    @State private var statusOK: Bool?
    @State private var testing = false
    @State private var showLogoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "设置",
                       subtitle: "服务器与分享码",
                       showsBack: true,
                       onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 14) {
                    MDCard {
                        VStack(alignment: .leading, spacing: 14) {
                            MDTextField(title: "服务器地址",
                                        text: $server,
                                        icon: "server.rack",
                                        keyboard: .URL,
                                        submitLabel: .next)
                            MDTextField(title: "分享码",
                                        text: $sharecode,
                                        icon: "key",
                                        submitLabel: .done,
                                        onSubmit: save)

                            if !status.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: statusOK == true ? "checkmark.circle" :
                                            (statusOK == false ? "exclamationmark.circle" : "arrow.triangle.2.circlepath"))
                                        .font(.system(size: 13))
                                    Text(status).font(.system(size: 13))
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(statusOK == true ? MD3.primary : (statusOK == false ? MD3.error : MD3.onSurfaceVariant))
                            }

                            MDPrimaryButton(title: testing ? "测试中…" : "保存并测试连接",
                                            icon: "wifi",
                                            enabled: !testing,
                                            action: save)
                        }
                    }

                    MDCard(padding: 0) {
                        VStack(spacing: 0) {
                            MDRow(icon: "trash.slash",
                                  title: "清空缩略图缓存",
                                  subtitle: "释放本机缓存占用",
                                  showsChevron: false) {
                                ThumbnailStore.shared.clearDisk()
                                toast.show("缩略图缓存已清空")
                            }
                            Divider().overlay(MD3.outlineVariant)
                            MDRow(icon: "arrow.clockwise.circle",
                                  title: "清除全部缓存",
                                  subtitle: "缩略图 + 下载文件 + 临时文件",
                                  showsChevron: false) {
                                clearAllCache()
                            }
                            Divider().overlay(MD3.outlineVariant)
                            MDRow(icon: "square.split.2x2",
                                  title: "上传分片大小",
                                  subtitle: "当前：\(chunkSizeMB) MB",
                                  showsChevron: true) {
                                showChunkSizePicker = true
                            }
                            Divider().overlay(MD3.outlineVariant)
                            MDRow(icon: "doc.on.doc",
                                  title: "当前分享码",
                                  subtitle: sharecode.isEmpty ? "（空）" : sharecode,
                                  showsChevron: false) {
                                UIPasteboard.general.string = sharecode
                                toast.show("已复制分享码")
                            }
                        }
                    }

                    MDCard(padding: 0) {
                        MDRow(icon: "rectangle.portrait.and.arrow.right",
                              iconTint: MD3.error,
                              iconBackground: MD3.errorContainer,
                              title: "退出登录",
                              subtitle: AppSettings.username.isEmpty ? nil : "当前账号：\(AppSettings.username)",
                              showsChevron: false,
                              tint: MD3.error) {
                            showLogoutConfirm = true
                        }
                    }

                    Text("协议：GET/POST + JSON，认证头 X-QF-Token 与 Authorization: Bearer；所有请求自动附加 sharecode 参数。")
                        .font(.system(size: 11))
                        .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .background(MD3.background.ignoresSafeArea())
        // 页面内提示层：跟随本页生命周期，不会被 sheet 层级遮住。
        // 复用全局 MDToast，与其他页面样式完全一致（品牌绿，不再是黑底）。
        .overlay(alignment: .bottom) {
            if let message = toast.message {
                MDToast(message: message)
                    .padding(.bottom, 48)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.message)
        .confirmationDialog("退出登录", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出", role: .destructive) {
                session.logout()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新输入账号密码")
        }
        .sheet(isPresented: $showChunkSizePicker) {
            NavigationStack {
                List {
                    ForEach([2, 5, 10, 20], id: \.self) { mb in
                        Button {
                            chunkSizeMB = mb
                            AppSettings.chunkSizeMB = mb
                            showChunkSizePicker = false
                            toast.show("分片大小：\(mb) MB")
                        } label: {
                            HStack {
                                Text("\(mb) MB")
                                Spacer()
                                if chunkSizeMB == mb {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(MD3.primary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("选择分片大小")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func clearAllCache() {
        // 清缩略图缓存
        ThumbnailStore.shared.clearDisk()
        // 清下载目录
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let downloadDir = docsDir.appendingPathComponent("下载")
            try? FileManager.default.removeItem(at: downloadDir)
        }
        // 清临时文件
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        toast.show("全部缓存已清除")
    }

    private func save() {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http") else {
            status = "地址需以 http:// 开头"
            statusOK = false
            return
        }
        AppSettings.server = trimmed
        AppSettings.sharecode = sharecode
        server = AppSettings.server
        testing = true
        statusOK = nil
        status = "正在测试连接…"

        Task {
            let result = await ApiClient.checkHealth(server: AppSettings.server,
                                                     sharecode: AppSettings.sharecode)
            status = result.message
            statusOK = result.ok
            testing = false
        }
    }
}
