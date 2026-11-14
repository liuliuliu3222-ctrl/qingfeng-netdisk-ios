import UIKit
import SwiftUI
import PhotosUI

struct MineView: View {

    @EnvironmentObject private var session: SessionStore

    var switchToFiles: () -> Void = {}

    @State private var showSettings = false
    @State private var showMember = false
    @State private var showTrash = false
    @State private var showBrowser = false
    @State private var showLogoutConfirm = false
    @State private var deletingAccount: String?
    @State private var avatarImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "我的",
                       subtitle: "清风网盘 3.2.1",
                       trailing: AnyView(MDIconButton(icon: "gearshape") { showSettings = true }))

            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    accountsCard
                    storageCard
                    entryCard
                    logoutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await session.refreshProfile() }
        }
        .background(MD3.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(session)
        }
        .sheet(isPresented: $showMember) {
            MemberSheet().environmentObject(session)
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .sheet(isPresented: $showBrowser) {
            BrowserView()
        }
        .confirmationDialog("退出登录", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出", role: .destructive) { session.logout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新输入账号密码")
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
            Text(account == AppSettings.username
                 ? "这是当前登录的账号，删除后将同时退出登录。"
                 : "将同时删除本机保存的密码；下次使用需重新输入。")
        }
        .onChange(of: photoPickerItem) { newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarImage = image
                    saveAvatar(image)
                }
            }
        }
        .onAppear {
            loadAvatar()
        }
    }

    private var profileCard: some View {
        MDCard(radius: MD3.radiusExtraLarge, padding: 18) {
            HStack(spacing: 14) {
                // 头像（可点击更换）
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    ZStack {
                        if let avatarImage = avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(MD3.primaryContainer)
                                .frame(width: 60, height: 60)
                            Text(avatarLetter)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(MD3.onPrimaryContainer)
                        }
                        // 编辑图标
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                        }
                        .frame(width: 60, height: 60)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.me.username.isEmpty ? AppSettings.username : session.me.username)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MD3.onSurface)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                        Text(session.me.tierName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(MD3.onPrimaryContainer)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MD3.primaryContainer)
                    .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                Button {
                    showMember = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                        Text("升级")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(MD3.primary)
                    .frame(width: 48, height: 48)
                    .background(MD3.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avatarLetter: String {
        let name = session.me.username.isEmpty ? AppSettings.username : session.me.username
        return name.isEmpty ? "?" : String(name.prefix(1)).uppercased()
    }

    // 头像存储
    private func saveAvatar(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(data, forKey: "custom_avatar")
        }
    }

    private func loadAvatar() {
        if let data = UserDefaults.standard.data(forKey: "custom_avatar"),
           let image = UIImage(data: data) {
            avatarImage = image
        }
    }

    /// 已保存的账号：一键切换，长按 / 点垃圾桶删除
    private var accountsCard: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MD3.onSurfaceVariant)
                    Text("已保存的账号")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MD3.onSurfaceVariant)
                    Spacer(minLength: 0)
                    Text("点按切换 · 长按删除")
                        .font(.system(size: 11))
                        .foregroundStyle(MD3.onSurfaceVariant.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

                // accountsRevision 变化（增删/切换账号）时强制重建列表
                let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
                if accounts.isEmpty {
                    Text("暂无其他已保存账号，登录时勾选即可记住")
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                } else {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider().overlay(MD3.outlineVariant).padding(.leading, 60)
                        }
                        accountRow(account,
                                   isCurrent: account == AppSettings.username)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: String, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            Button {
                if isCurrent {
                    ToastCentre.shared.show("当前已登录该账号")
                } else {
                    session.switchAccount(to: account)
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isCurrent ? MD3.primary : MD3.primaryContainer)
                            .frame(width: 38, height: 38)
                        Text(String(account.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isCurrent ? MD3.onPrimary : MD3.onPrimaryContainer)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MD3.onSurface)
                            .lineLimit(1)
                        Text(isCurrent ? "当前登录" : AppSettings.hasPasswordSaved(for: account) ? "已保存密码" : "未保存密码")
                            .font(.system(size: 11))
                            .foregroundStyle(isCurrent ? MD3.primary : MD3.onSurfaceVariant)
                    }
                    Spacer(minLength: 6)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(MD3.primary)
                    }
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
        .padding(.horizontal, 16)
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

    private var storageCard: some View {
        MDCard(padding: 18) {
            HStack(spacing: 18) {
                ZStack {
                    RingProgress(fraction: session.me.fraction, lineWidth: 9)
                        .frame(width: 78, height: 78)
                    Text("\(session.me.percent)%")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MD3.onSurface)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("已用 \(ByteText.string(session.me.usedBytes))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MD3.onSurface)
                    Text("总空间 \(ByteText.string(session.me.quotaBytes))")
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant)
                    Text("剩余 \(ByteText.string(max(0, session.me.quotaBytes - session.me.usedBytes)))")
                        .font(.system(size: 12))
                        .foregroundStyle(MD3.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var entryCard: some View {
        MDCard(padding: 0) {
            VStack(spacing: 0) {
                MDRow(icon: "folder", title: "全部文件") { switchToFiles() }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "trash", title: "回收站") { showTrash = true }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "globe", title: "网页浏览") { showBrowser = true }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "crown", title: "会员中心", subtitle: "查看等级与配额") { showMember = true }
                Divider().overlay(MD3.outlineVariant)
                MDRow(icon: "gearshape", title: "设置", subtitle: AppSettings.server) { showSettings = true }
            }
        }
    }

    private var logoutCard: some View {
        MDCard(padding: 0) {
            MDRow(icon: "rectangle.portrait.and.arrow.right",
                  iconTint: MD3.error,
                  iconBackground: MD3.errorContainer,
                  title: "退出登录",
                  showsChevron: false,
                  tint: MD3.error) {
                showLogoutConfirm = true
            }
        }
    }
}
