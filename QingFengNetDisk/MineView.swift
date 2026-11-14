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
    @State private var showAccountSwitch = false
    @State private var avatarImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            MDTopAppBar(title: "我的",
                       subtitle: "清风网盘 3.2.2",
                       trailing: AnyView(MDIconButton(icon: "gearshape") { showSettings = true }))

            ScrollView {
                VStack(spacing: 14) {
                    profileCard
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
        .sheet(isPresented: $showAccountSwitch) {
            AccountSwitchSheet().environmentObject(session)
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
                // 头像（可点击更换）+ 右下角切换账号角标
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

                // 切换账号入口（3.2.0 同款：头像旁边的小按钮）
                switchButton

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

    /// 切换账号按钮（头像旁边，点按进入账号管理二级页）
    private var switchButton: some View {
        Button {
            showAccountSwitch = true
        } label: {
            ZStack {
                Circle()
                    .fill(MD3.primaryContainer)
                    .frame(width: 30, height: 30)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MD3.onPrimaryContainer)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换账号")
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
