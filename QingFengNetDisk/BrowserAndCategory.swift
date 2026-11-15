import UIKit
import SwiftUI
import SafariServices

// MARK: - 分类浏览（图片 / 视频 / 文档 / 音频 / 压缩包）

struct CategoryView: View {

    let title: String
    let type: String

    @Environment(\.dismiss) private var dismiss

    @State private var items: [QFFile] = []
    @State private var loading = false
    @State private var previewTarget: QFFile?

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: title,
                       subtitle: "\(items.count) 个文件",
                       showsBack: true,
                       onBack: { dismiss() },
                       trailing: AnyView(MDIconButton(icon: "arrow.clockwise") {
                           Task { await load() }
                       }))

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty && !loading {
                        MDEmptyState(icon: "tray",
                                     title: "这里还没有文件",
                                     detail: "上传后会按类型自动归类")
                            .frame(minHeight: 360)
                    } else {
                        MDCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, file in
                                    Button {
                                        previewTarget = file
                                    } label: {
                                        FileRow(file: file)
                                    }
                                    .buttonStyle(.plain)
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
        .sheet(item: $previewTarget) { file in
            PreviewView(file: file)
        }
    }

    private func load() async {
        loading = true
        do {
            items = try await ApiClient.shared.category(type)
        } catch {
            // 刷新失败或被取消：保留现有列表，不清空、不弹提示
        }
        loading = false
    }
}

// MARK: - 网页版入口
// Android 版是自绘 WebView 内置浏览器（地址栏 + 九宫格导航 + 多标签）。
// iOS 不允许自绘 WebView 内核，这里改为系统 SFSafariViewController：
// 功能等价（打开网页版、登录态由 Safari 维护），Android 特有的九宫格快捷站点
// 与自绘地址栏在 iOS 上隐藏。

struct BrowserView: View {

    private var targetURL: URL? {
        var path = "/"
        let code = AppSettings.sharecode
        if !code.isEmpty {
            path += "?sharecode=" + ApiClient.encode(code)
        }
        return URL(string: AppSettings.server + path)
    }

    var body: some View {
        Group {
            if let url = targetURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            } else {
                MDEmptyState(icon: "globe",
                             title: "无法打开网页版",
                             detail: "请到设置页检查服务器地址")
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(MD3.primary)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
