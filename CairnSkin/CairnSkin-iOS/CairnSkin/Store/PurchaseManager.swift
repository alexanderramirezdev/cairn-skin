//
//  PurchaseManager.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The one-time unlock. Free users get a single tracking area; buying
//  removes the limit.
//
//  WHY A ONE-TIME PURCHASE AND NOT A SUBSCRIPTION:
//  There's no server, no account, and no ongoing cost to the developer,
//  so there's nothing to justify a recurring charge. People notice that,
//  and they're right to.
//
//  WHAT IS AND ISN'T GATED:
//  Gated: creating more than one tracking area.
//  Never gated: everything about the area you already have — guided
//  capture, comparison, the photo grid, reminders, Face ID, PDF export,
//  and above all the photos themselves. Someone who took a hundred
//  photos and doesn't pay keeps every one of them and can keep adding
//  more. The wall appears only when they want a SECOND area, which is
//  after they've already decided the app is worth using.
//
//  That line matters. Holding someone's own health photos hostage would
//  be indefensible for an app whose entire pitch is that your data is
//  yours.
//

import Foundation
import StoreKit
import Observation

@Observable
@MainActor
final class PurchaseManager {

    /// Must match the product ID configured in App Store Connect.
    static let unlimitedAreasID = "com.aramirez.CairnSkin.unlimited"

    /// How many areas someone can create without buying.
    static let freeAreaLimit = 1

    private(set) var product: Product?
    private(set) var hasUnlimited = false
    private(set) var isLoading = false
    private(set) var purchaseError: String?

    /// Watches for entitlement changes that happen outside a purchase we
    /// initiated: Family Sharing, a purchase made on another device, an
    /// App Store refund. Without this the app can be wrong about what the
    /// user owns until the next launch.
    ///
    /// NO deinit CANCELS THIS, deliberately. `deinit` is nonisolated in
    /// Swift 6 (deallocation can happen on any thread), so it cannot touch
    /// a main-actor-isolated property like this one.
    ///
    /// It doesn't need to. The closure captures `self` weakly, so the task
    /// holds nothing alive, and this object is created once at launch and
    /// lives for the process. Cancelling on deinit was defending against a
    /// deallocation that never happens.
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let transaction = try? update.payloadValue else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    /// Price string for the paywall, localized by StoreKit to the user's
    /// storefront. Never hardcode "$4.99" in the UI — it's wrong in most
    /// of the world.
    var displayPrice: String {
        product?.displayPrice ?? ""
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Self.unlimitedAreasID])
            product = products.first
        } catch {
            // A failed product load is not the same as "not purchased".
            // Leave entitlement alone and let the paywall show a retry.
            purchaseError = "Couldn't reach the App Store. Check your connection and try again."
        }

        await refreshEntitlements()
    }

    /// The source of truth for what the user owns.
    ///
    /// `currentEntitlements` is verified by StoreKit against the App
    /// Store, so this can't be spoofed by writing to UserDefaults, which
    /// is why entitlement is never cached there.
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue else { continue }
            if transaction.productID == Self.unlimitedAreasID && transaction.revocationDate == nil {
                hasUnlimited = true
                return
            }
        }
        hasUnlimited = false
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            purchaseError = "This purchase isn't available right now."
            return false
        }

        purchaseError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = try? verification.payloadValue else {
                    purchaseError = "That purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return true

            case .userCancelled:
                // Not an error. Say nothing and let them carry on.
                return false

            case .pending:
                // Ask To Buy, or a payment method needing approval. The
                // Transaction.updates listener above will catch it when it
                // resolves, which may be days later.
                purchaseError = "This purchase is waiting for approval. It'll unlock automatically once approved."
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Something went wrong with the purchase. You haven't been charged."
            return false
        }
    }

    /// App Review requires a way to restore purchases on a new device.
    /// An app without one gets rejected, and reasonably so: people who
    /// paid should not have to pay twice.
    func restore() async {
        isLoading = true
        defer { isLoading = false }

        purchaseError = nil
        try? await AppStore.sync()
        await refreshEntitlements()

        if !hasUnlimited {
            purchaseError = "No previous purchase found for this Apple Account."
        }
    }

    /// Whether another area can be created.
    ///
    /// Deliberately allows existing areas above the limit. If someone has
    /// three areas from an earlier version, they keep all three and simply
    /// can't add a fourth. Taking their data away would be a worse thing
    /// to do than losing the sale.
    func canAddArea(currentCount: Int) -> Bool {
        hasUnlimited || currentCount < Self.freeAreaLimit
    }
}
