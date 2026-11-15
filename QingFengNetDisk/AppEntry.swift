import SwiftUI
import UIKit

@main
struct QingFengApp: App {

    @StateObject private var session = SessionStore()

    init() {
        // 全局隐藏滚动条：SwiftUI ScrollView / 系统 List  underlying 的 UIScrollView
        // 统一关掉垂直、水平指示器，仅隐藏灰黑色滚动条，不影响滑动浏览与交互。
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        UITableView.appearance().showsVerticalScrollIndicator = false
        UITableView.appearance().showsHorizontalScrollIndicator = false
        UICollectionView.appearance().showsVerticalScrollIndicator = false
        UICollectionView.appearance().showsHorizontalScrollIndicator = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(TransferStore.shared)
                .tint(MD3.primary)
        }
    }
}

/// 登录态路由：未登录进登录页，已登录进主界面
struct RootView: View {

    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ZStack {
            MD3.background.ignoresSafeArea()
            if session.isLoggedIn {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
            ToastOverlay()
        }
        .animation(.easeInOut(duration: 0.22), value: session.isLoggedIn)
        // 环境级别隐藏滚动指示器：覆盖所有子页面与 sheet 中呈现的 ScrollView/List，
        // 保留正常滑动浏览，只隐藏灰黑色滚动条，不影响任何交互与内容展示。
        .scrollIndicators(.hidden)
    }
}

/// 主框架：系统 TabView（iOS 26 原生液态玻璃底栏）
struct MainTabView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView(switchToFiles: { selection = 1 })
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)
            FilesView()
                .tabItem { Label("文件", systemImage: "folder") }
                .tag(1)
            TransferView()
                .tabItem { Label("传输", systemImage: "arrow.up.arrow.down") }
                .tag(2)
            MineView(switchToFiles: { selection = 1 })
                .tabItem { Label("我的", systemImage: "person") }
                .tag(3)
        }
        .task {
            Notifier.requestAuthorization()
            await session.refreshProfile()
        }
    }
}
