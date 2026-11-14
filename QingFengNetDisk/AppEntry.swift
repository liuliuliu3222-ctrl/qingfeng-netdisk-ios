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
