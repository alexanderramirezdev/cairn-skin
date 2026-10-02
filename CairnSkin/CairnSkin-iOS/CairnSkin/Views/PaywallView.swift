//
//  PaywallView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The one-time unlock screen, shown when someone tries to create a
//  second tracking area.
//
//  TONE:
//  This appears to someone who has already used the app enough to want
//  another area, so it doesn't need to sell them on the concept. It needs
//  to say what they get, what it costs, and get out of the way. No
//  countdown, no "limited time", no dark patterns — the app's whole
//  positioning is that it treats the user straight, and a manipulative
//  paywall would undo that in one screen.
//

import SwiftUI

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful purchase, so the caller can carry on with
    /// whatever the user was trying to do.
    let onPurchased: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stacked-stones mark, matching the app icon. Drawn
                    // inline rather than shared: it appears in exactly two
                    // places and extracting it would be indirection for
                    // its own sake.
                    ZStack {
                        Ellipse().fill(Color(red: 0.34, green: 0.39, blue: 0.51))
                            .frame(width: 62, height: 19).offset(y: 22)
                        Ellipse().fill(Color(red: 0.42, green: 0.49, blue: 0.61))
                            .frame(width: 48, height: 17).offset(y: 6)
                        Ellipse().fill(Color(red: 0.89, green: 0.93, blue: 0.96))
                            .frame(width: 35, height: 15).offset(y: -8)
                        Ellipse().fill(Color(red: 0.53, green: 0.84, blue: 0.84))
                            .frame(width: 22, height: 11).offset(y: -21)
                    }
                    .frame(height: 70)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("Track as many areas as you like")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("Cairn Skin is free for one area. A single purchase adds as many as you want, each with its own baseline and history.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("square.grid.2x2", "Unlimited tracking areas")
                        benefit("clock.arrow.circlepath", "Every photo you've already taken stays yours")
                        benefit("lock.shield", "Still no account, still nothing uploaded")
                        benefit("checkmark.circle", "One payment, not a subscription")
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                if await purchases.purchase() {
                                    onPurchased()
                                    dismiss()
                                }
                            }
                        } label: {
                            Group {
                                if purchases.isLoading {
                                    ProgressView()
                                } else if purchases.displayPrice.isEmpty {
                                    Text("Unlock")
                                } else {
                                    Text("Unlock for \(purchases.displayPrice)")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchases.isLoading || purchases.product == nil)

                        Button("Restore Purchase") {
                            Task { await purchases.restore() }
                        }
                        .font(.subheadline)
                        .disabled(purchases.isLoading)
                    }
                    .padding(.horizontal, 28)

                    if let error = purchases.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }

                    Text("Your existing area and every photo in it stay available whether or not you buy this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .task {
                if purchases.product == nil {
                    await purchases.load()
                }
            }
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
