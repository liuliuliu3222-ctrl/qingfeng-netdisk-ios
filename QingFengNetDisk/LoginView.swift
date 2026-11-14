import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var username = ""
    @State private var password = ""
    @State private var registerMode = false
    @State private var busy = false
    @State private var message = ""
    @State private var isError = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if AppSettings.hasSavedAccounts {
                    SavedAccountsCard(session: session)
                }

                MDCard(radius: MD3.radiusExtraLarge, padding: 20) {
                    VStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text(registerMode ? "创建账号" : "账号登录")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(MD3.onSurface)
                            Spacer()
                            Text(AppSettings.sharecode)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MD3.onPrimaryContainer)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(MD3.primaryContainer)
                                .clipShape(Capsule())
                        }

                        MDTextField(title: "用户名",
                                    text: $username,
                                    icon: "person",
                                    keyboard: .default,
                                    submitLabel: .next)

                        MDTextField(title: "密码",
                                    text: $password,
                                    icon: "lock",
                                    secure: true,
                                    submitLabel: .go,
                                    onSubmit: submit)

                        if !message.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: isError ? "exclamationmark.circle" : "info.circle")
                                    .font(.system(size: 13))
                                Text(message)
                                    .font(.system(size: 13))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(isError ? MD3.error : MD3.onSurfaceVariant)
                        }

                        MDPrimaryButton(title: registerMode ? "注册并进入" : "登录",
                                        icon: nil,
                                        enabled: !busy,
                                        action: submit)

                        Button {
                            registerMode.toggle()
                            message = ""
                            isError = false
                        } label: {
                            Text(registerMode ? "已有账号？去登录" : "还没有账号？去注册")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MD3.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack").font(.system(size: 12))
                        Text("服务器地址：\(AppSettings.server)")
                            .lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(MD3.onSurfaceVariant)
                }
                .buttonStyle(.plain)

                Text("清风网盘 iOS 版 · 3.4.2")
                    .font(.system(size: 11))
                    .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 40)
        }
        .background(MD3.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(session)
        }
    }

    private func quickLogin(_ account: String) {
        let password = AppSettings.storedPassword(for: account)
        guard !password.isEmpty, !busy else { return }
        busy = true
        isError = false
        message = "正在登录 \(account)…"
        Task {
            do {
                let token = try await ApiClient.shared.auth(username: account,
                                                            password: password,
                                                            register: false)
                session.signIn(token: token, username: account, password: password)
                await session.refreshProfile()
                ToastCentre.shared.show("登录成功")
            } catch {
                message = "登录失败：\(error.localizedDescription)"
                isError = true
            }
            busy = false
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MD3.primaryContainer)
                    .frame(width: 78, height: 78)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(MD3.primary)
            }
            Text("清风网盘")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(MD3.onSurface)
            Text("私有云 · 随时存取你的文件")
                .font(.system(size: 13))
                .foregroundStyle(MD3.onSurfaceVariant)
        }
    }

    private func submit() {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            message = "请输入用户名和密码"
            isError = true
            return
        }
        guard !busy else { return }
        busy = true
        isError = false
        message = "处理中…"

        let mode = registerMode
        Task {
            do {
                let token = try await ApiClient.shared.auth(username: user,
                                                            password: password,
                                                            register: mode)
                session.signIn(token: token, username: user, password: password)
                await session.refreshProfile()
                ToastCentre.shared.show(mode ? "注册成功，欢迎加入！" : "登录成功")
            } catch {
                message = error.localizedDescription
                isError = true
            }
            busy = false
        }
    }
}

// MARK: - 已保存的账号卡片（登录页）

/// 登录页的已保存账号列表：点按直接登录，长按或点垃圾桶删除
struct SavedAccountsCard: View {
    @ObservedObject var session: SessionStore
    @State private var deletingAccount: String?

    var body: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        if !accounts.isEmpty {
            MDCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.clock")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MD3.onSurfaceVariant)
                        Text("已保存的账号")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MD3.onSurfaceVariant)
                        Spacer(minLength: 0)
                        Text("点按登录 · 长按删除")
                            .font(.system(size: 11))
                            .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider().overlay(MD3.outlineVariant).padding(.leading, 60)
                        }
                        row(account)
                    }
                }
            }
            .confirmationDialog("删除已保存的账号",
                                isPresented: .init(get: { deletingAccount != nil },
                                                   set: { if !$0 { deletingAccount = nil } }),
                                titleVisibility: .visible,
                                presenting: deletingAccount) { account in
                Button("删除 \(account)", role: .destructive) {
                    withAnimation { session.deleteSavedAccount(account) }
                    ToastCentre.shared.show("已删除账号 \(account)")
                }
                Button("取消", role: .cancel) {}
            } message: { account in
                Text("将同时删除本机保存的密码；下次使用需重新输入。")
            }
        }
    }

    private func row(_ account: String) -> some View {
        HStack(spacing: 12) {
            Button {
                quickLogin(account)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(MD3.primaryContainer)
                            .frame(width: 38, height: 38)
                        Text(String(account.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MD3.onPrimaryContainer)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MD3.onSurface)
                            .lineLimit(1)
                        Text(AppSettings.hasPasswordSaved(for: account) ? "点按直接登录" : "未保存密码")
                            .font(.system(size: 11))
                            .foregroundStyle(MD3.onSurfaceVariant)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: AppSettings.hasPasswordSaved(for: account) ? "arrow.right.circle" : "exclamationmark.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(AppSettings.hasPasswordSaved(for: account) ? MD3.primary : MD3.error)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                deletingAccount = account
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MD3.error)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MD3.errorContainer.opacity(0.5)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除账号 \(account)")
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                deletingAccount = account
            } label: {
                Label("删除该账号", systemImage: "trash")
            }
        }
    }

    private func quickLogin(_ account: String) {
        let password = AppSettings.storedPassword(for: account)
        guard AppSettings.hasPasswordSaved(for: account) else {
            ToastCentre.shared.show("该账号未保存密码，请输入密码登录")
            return
        }
        guard !password.isEmpty else { return }
        Task { @MainActor in
            do {
                let token = try await ApiClient.shared.auth(username: account,
                                                            password: password,
                                                            register: false)
                session.signIn(token: token, username: account, password: password)
                await session.refreshProfile()
                ToastCentre.shared.show("登录成功")
            } catch {
                ToastCentre.shared.show("登录失败：\(error.localizedDescription)")
            }
        }
    }
}
