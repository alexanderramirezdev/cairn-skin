//
//  FreeTierTests.swift
//  CairnSkinTests
//
//  WHAT THESE GUARD:
//  The free tier's promise: one area, fully usable, forever. Someone who
//  never pays must always be able to create their first area and must
//  hit the paywall only on the second.
//
//  NOTE: needs PurchaseManager.swift, which is in the shipped app but not
//  yet in the GitHub repo. If this file fails to compile, that file is
//  missing from the project.
//
//  Only the not-purchased path is tested. `hasUnlimited` is set solely by
//  StoreKit's verified entitlements and can't be faked from a test, which
//  is deliberate: an entitlement a test could flip is one an attacker
//  could flip too. The purchased path is covered by the StoreKit
//  configuration file and manual testing.
//

import Testing
@testable import CairnSkin

@MainActor
@Suite("Free tier area limit")
struct FreeTierTests {

    @Test func freeLimitIsOneArea() {
        #expect(PurchaseManager.freeAreaLimit == 1)
    }

    @Test func freeUserCanCreateTheirFirstArea() {
        let purchases = PurchaseManager()
        #expect(purchases.canAddArea(currentCount: 0))
    }

    @Test func freeUserHitsThePaywallOnTheSecondArea() {
        let purchases = PurchaseManager()
        #expect(!purchases.canAddArea(currentCount: 1))
    }

    /// A tester who made several areas before the paywall existed keeps
    /// them all. They just can't add another. This only checks the gate
    /// holds; the "keeps them" half is that nothing ever deletes areas
    /// based on purchase state, which is worth keeping true.
    @Test func userAlreadyOverTheLimitIsGatedNotPunished() {
        let purchases = PurchaseManager()
        #expect(!purchases.canAddArea(currentCount: 3))
    }

    /// The product ID has to match App Store Connect exactly, or the
    /// paywall loads no product in production and the button stays
    /// disabled with no error.
    @Test func productIDMatchesAppStoreConnect() {
        #expect(PurchaseManager.unlimitedAreasID == "com.aramirez.CairnSkin.unlimited")
    }
}
