import Foundation
import StoreKit

/// App Store Connect 中需创建同 ID 的 IAP：消耗型「10 次」、非消耗型「永久」。
enum IAPProductID {
    static let genPack10 = "com.blackwhale.YujieTTS.genpack10"
    static let lifetime = "com.blackwhale.YujieTTS.lifetime"
    static let all: [String] = [genPack10, lifetime]
}

/// 首次成功生成免费；之后需消耗型次数或永久解锁。次数仅存本机（消耗型无法跨设备恢复余额）。
@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var creditBalance: Int
    @Published private(set) var freeGenerationConsumed: Bool
    @Published private(set) var lifetimeUnlocked: Bool
    @Published var purchaseError: String?
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private let kFree = "YujieTTS.freeGenerationConsumed"
    private let kCredits = "YujieTTS.creditBalance"
    private let kLifetimeCache = "YujieTTS.lifetimeUnlockedCache"
    private let kProcessedTx = "YujieTTS.processedTransactionIDs"

    init() {
        creditBalance = defaults.integer(forKey: kCredits)
        freeGenerationConsumed = defaults.bool(forKey: kFree)
        lifetimeUnlocked = defaults.bool(forKey: kLifetimeCache)
        updatesTask = Task { await self.listenForTransactions() }
        Task { await loadProducts(); await refreshLifetimeFromStore() }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 是否允许开始一次新的生成（未计成功/失败，成功后在 UI 层调用 `recordSuccessfulGeneration()`）
    var canStartGeneration: Bool {
        if lifetimeUnlocked { return true }
        if !freeGenerationConsumed { return true }
        return creditBalance > 0
    }

    func statusLine() -> String {
        if lifetimeUnlocked { return "已解锁：永久生成" }
        if !freeGenerationConsumed { return "首次生成免费" }
        if creditBalance > 0 { return "剩余 \(creditBalance) 次生成" }
        return "免费次数已用完，购买后可继续生成"
    }

    /// 仅在引擎返回成功并写入历史后调用
    func recordSuccessfulGeneration() {
        if lifetimeUnlocked { return }
        if !freeGenerationConsumed {
            freeGenerationConsumed = true
            defaults.set(true, forKey: kFree)
            return
        }
        if creditBalance > 0 {
            creditBalance -= 1
            defaults.set(creditBalance, forKey: kCredits)
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: IAPProductID.all)
            products = loaded.sorted { $0.id < $1.id }
            purchaseError = products.isEmpty ? "未找到内购商品，请在 App Store Connect 配置后重试。" : nil
        } catch {
            purchaseError = error.localizedDescription
            products = []
        }
    }

    func refreshLifetimeFromStore() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == IAPProductID.lifetime else { continue }
            guard transaction.revocationDate == nil else { continue }
            applyLifetimeUnlocked()
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    // 与 Transaction.updates 共用去重，避免重复发放
                    await process(transaction)
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "订单处理中，请稍候在「设置」中查看。"
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshLifetimeFromStore()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func product(genPack: Bool) -> Product? {
        let id = genPack ? IAPProductID.genPack10 : IAPProductID.lifetime
        return products.first { $0.id == id }
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await process(transaction)
            }
        }
    }

    private func process(_ transaction: Transaction) async {
        if transaction.revocationDate != nil {
            if transaction.productID == IAPProductID.lifetime {
                lifetimeUnlocked = false
                defaults.set(false, forKey: kLifetimeCache)
            }
            await transaction.finish()
            return
        }

        let tid = String(transaction.id)
        var processed = defaults.stringArray(forKey: kProcessedTx) ?? []
        if processed.contains(tid) {
            await transaction.finish()
            return
        }

        switch transaction.productID {
        case IAPProductID.genPack10:
            creditBalance += 10
            defaults.set(creditBalance, forKey: kCredits)
        case IAPProductID.lifetime:
            applyLifetimeUnlocked()
        default:
            await transaction.finish()
            return
        }

        processed.append(tid)
        defaults.set(processed, forKey: kProcessedTx)
        await transaction.finish()
    }

    private func applyLifetimeUnlocked() {
        guard !lifetimeUnlocked else { return }
        lifetimeUnlocked = true
        defaults.set(true, forKey: kLifetimeCache)
    }
}
