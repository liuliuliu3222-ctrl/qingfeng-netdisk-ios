import SwiftUI

@main
struct QingFengApp: App {

    @StateObject private var session = SessionStore()

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
    }
}

/// 主框架：MD3 顶部栏 + 内容 + 底部导航 + FAB
struct MainTabView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var selection = 0

    private let navigationItems: [MDNavigationBar.Item] = [
        .init(title: "首页", icon: "house", activeIcon: "house.fill"),
        .init(title: "文件", icon: "folder", activeIcon: "folder.fill"),
        .init(title: "传输", icon: "arrow.up.arrow.down", activeIcon: "arrow.up.arrow.down.circle.fill"),
        .init(title: "我的", icon: "person", activeIcon: "person.fill")
    ]

    var body: some View {
        ZStack {
            // 内容区域（四个页面常驻）
            ZStack {
                HomeView(switchToFiles: { selection = 1 })
                    .opacity(selection == 0 ? 1 : 0)
                    .allowsHitTesting(selection == 0)
                FilesView()
                    .opacity(selection == 1 ? 1 : 0)
                    .allowsHitTesting(selection == 1)
                TransferView()
                    .opacity(selection == 2 ? 1 : 0)
                    .allowsHitTesting(selection == 2)
                MineView(switchToFiles: { selection = 1 })
                    .opacity(selection == 3 ? 1 : 0)
                    .allowsHitTesting(selection == 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 悬浮底栏（iOS 26 液态玻璃 / 旧系统 MD3 回退）
            VStack {
                Spacer()
                LiquidGlassDockBar(items: navigationItems, selection: $selection)
            }
        }
        .background(MD3.background)
        .task {
            Notifier.requestAuthorization()
            await session.refreshProfile()
        }
    }
}
