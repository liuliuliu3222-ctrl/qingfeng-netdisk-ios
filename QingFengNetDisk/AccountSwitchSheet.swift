import UIKit
import SwiftUI

/// 切换账号（「我的 → 切换」进入）。
/// 按目标截图（图2）逐像素测量 1:1 重建，与 3.2.0 版式的差异全部落地：
/// - 系统分组灰底 + 白色卡片（左右边距 16pt，圆角 30pt；矮卡片自动收敛为胶囊）
/// - 居中黑色标题「切换账号」（17pt 半粗体，无返回键）
/// - 节标题「已保存的账号」17pt 半粗体、灰色 #85858B、左缩进 16pt（旧版为 13pt / 33pt）
/// - 行：纯色 #2FAE7A 圆头像 24pt + 白色 person.fill 人像剪影 + 绿色用户名 17pt
///   + 当前账号绿色对勾；行高 58pt，行内边距 18pt（旧版为渐变圆 + 首字母）
/// - 多账号同卡展示，行间 1pt 分隔线 #E7E7E8（leading 52pt / trailing 16pt）
/// - 第二张卡片：纯绿色线条 person.badge.plus（无圆形底）+ 绿色「添加新账号」
///   （旧版为白色小图标套在渐变圆里）
/// 逻辑：点按账号直接切换；长按账号删除；「添加新账号」不再弹确认框、不再退出登录，
/// 直接以可关闭的全屏登录页呈现（隐藏已保存账号栏、带返回按钮），当前会话始终保留。
struct AccountSwitchSheet: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var deletingAccount: String?
    @State private var showAddAccountLogin = false

    // 目标截图实测配色：全页面统一纯色 #2FAE7A，不再使用渐变
    private let qfGreen = MD3.primary                              // 浅色 = #2FAE7A
    private let sectionTitleColor = Color.adaptive(light: 0x85858B, dark: 0x98989F)
    private let separatorColor = Color.adaptive(light: 0xE7E7E8, dark: 0x3A3A3C)
    private let cardRadius: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            // 居中标题（无返回按钮，下滑手势关闭）
            Text("切换账号")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .frame(height: 52)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 节标题：17pt 半粗体，与卡片左缘内缩 16pt
                    Text("已保存的账号")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(sectionTitleColor)
                        .padding(.leading, 16)
                        .padding(.bottom, 13)

                    accountCard

                    Spacer(minLength: 0).frame(height: 35)

                    addAccountCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        // 「添加新账号」：不弹窗、不退出登录，直接前往登录页。
        // 全屏覆盖而非替换 root，所以点「返回」即可回到本页，再下滑即回云盘。
        .fullScreenCover(isPresented: $showAddAccountLogin) {
            LoginView(addAccountMode: true,
                      onClose: {
                          showAddAccountLogin = false
                      },
                      onSignedIn: {
                          // 登录成功已切到新账号：先收起登录页，再收起本页回到云盘
                          showAddAccountLogin = false
                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                              dismiss()
                          }
                      })
                .environmentObject(session)
        }
        // 删除账号确认：系统原生居中弹窗（与设置页退出登录一致），文案/按钮/执行逻辑不变
        .alert("删除账号",
               isPresented: .init(get: { deletingAccount != nil },
                                  set: { if !$0 { deletingAccount = nil } }),
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
    }

    // MARK: - 账号卡片（白卡圆角 30，行高 58，多账号同卡 + 分隔线）

    private var accountCard: some View {
        let accounts = session.accountsRevision >= 0 ? AppSettings.savedAccounts : []
        return Group {
            if accounts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(uiColor: .systemGray))
                    Text("暂无已保存的账号")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(uiColor: .systemGray))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: cardRadius))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element) { index, account in
                        if index > 0 {
                            Divider()
                                .overlay(separatorColor)
                                .padding(.leading, 52)
                                .padding(.trailing, 16)
                        }
                        accountRow(account, isCurrent: account == AppSettings.username)
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: cardRadius))
            }
        }
    }

    /// 纯色圆底 + 白色人像剪影（替代旧的渐变圆 + 首字母）
    private var accountAvatar: some View {
        ZStack {
            Circle()
                .fill(qfGreen)
                .frame(width: 24, height: 24)
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
    }

    private func accountRow(_ account: String, isCurrent: Bool) -> some View {
        // 用「非 Button 视图 + 两个独立手势」替代 Button：
        // Button 内建的 tap 手势会与 onLongPressGesture 竞争，导致长按删除确认不弹出。
        // 拆开后短按=切换账号、长按=弹出删除确认，互不干扰；
        // 同时不使用系统 contextMenu，长按态与常态视觉一致、无抬起外阴影。
        HStack(spacing: 12) {
            accountAvatar
            Text(account)
                .font(.system(size: 17))
                .foregroundStyle(qfGreen)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(qfGreen)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrent {
                ToastCentre.shared.show("当前已登录该账号")
            } else {
                session.switchAccount(to: account)
                dismiss()
            }
        }
        // 高优先级长按：长按成功时压制 tap，只弹删除确认，避免切换账号/关闭页面抢先触发。
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // 长按命中给出触感反馈，再弹出删除确认
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    deletingAccount = account
                }
        )
    }

    // MARK: - 添加新账号卡片（纯绿色线条图标，无圆形底）

    private var addAccountCard: some View {
        Button {
            showAddAccountLogin = true
        } label: {
            HStack(spacing: 12) {
                // 图标本身约 26pt 高；布局宽度仍按 24pt 计，使文字与账号行左缘对齐
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(qfGreen)
                    .frame(width: 24, alignment: .leading)
                Text("添加新账号")
                    .font(.system(size: 17))
                    .foregroundStyle(qfGreen)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    }
}
