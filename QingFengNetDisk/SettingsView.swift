import UIKit
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var server = AppSettings.server
    @State private var sharecode = AppSettings.sharecode
    @State private var chunkSizeMB = AppSettings.chunkSizeMB
    @State private var showChunkSizePicker = false
    @State private var status = ""
    @State private var statusOK: Bool?
    @State private var testing = false

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
                                ToastCentre.shared.show("缩略图缓存已清空")
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
                            MDRow(icon: "link",
                                  title: "我的仓库",
                                  subtitle: "GitHub: qingfeng-netdisk-ios",
                                  showsChevron: true) {
                                if let url = URL(string: "https://github.com/liuliuliu3222-ctrl/qingfeng-netdisk-ios") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Divider().overlay(MD3.outlineVariant)
                            MDRow(icon: "doc.on.doc",
                                  title: "当前分享码",
                                  subtitle: sharecode.isEmpty ? "（空）" : sharecode,
                                  showsChevron: false) {
                                UIPasteboard.general.string = sharecode
                                ToastCentre.shared.show("已复制分享码")
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
                            session.logout()
                            dismiss()
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
        .sheet(isPresented: $showChunkSizePicker) {
            NavigationStack {
                List {
                    ForEach([2, 5, 10, 20], id: \.self) { mb in
                        Button {
                            chunkSizeMB = mb
                            AppSettings.chunkSizeMB = mb
                            showChunkSizePicker = false
                            ToastCentre.shared.show("分片大小：\(mb) MB")
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
        ToastCentre.shared.show("全部缓存已清除")
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
