import StoreKit
import SwiftUI

/// 免费次数用尽后的购买界面（¥1 / 10 次、¥9.9 永久需在 App Store Connect 配置对应价格档）
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchases: PurchaseManager

    var body: some View {
        VStack(spacing: 20) {
            Text("继续生成语音")
                .font(.title2.bold())

            Text("首次生成免费。之后可选择购买生成次数或一次解锁永久使用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let err = purchases.purchaseError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                purchaseRow(
                    title: "10 次生成",
                    subtitle: "消耗型，约 1 元（以 App Store 显示为准）",
                    product: purchases.product(genPack: true)
                )
                purchaseRow(
                    title: "永久生成",
                    subtitle: "非消耗型，约 9.9 元（以 App Store 显示为准）",
                    product: purchases.product(genPack: false)
                )
            }
            .frame(maxWidth: 420)

            HStack(spacing: 16) {
                Button("恢复购买") {
                    Task { await purchases.restorePurchases() }
                }
                .buttonStyle(.borderless)
                .disabled(purchases.isPurchasing)

                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)

            Text("购买将透过 Apple 账户扣款。消耗型次数仅存于本设备；永久权益可通过「恢复购买」同步。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(minWidth: 480)
        .onChange(of: purchases.creditBalance) { _, _ in
            if purchases.canStartGeneration { dismiss() }
        }
        .onChange(of: purchases.lifetimeUnlocked) { _, _ in
            if purchases.canStartGeneration { dismiss() }
        }
    }

    private func purchaseRow(title: String, subtitle: String, product: Product?) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let product {
                Button {
                    Task { await purchases.purchase(product) }
                } label: {
                    if purchases.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(product.displayPrice)
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(purchases.isPurchasing)
            } else {
                Text("加载中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
