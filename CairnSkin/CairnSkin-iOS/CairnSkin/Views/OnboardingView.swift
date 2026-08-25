//
//  OnboardingView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A three-page introduction shown once, on first launch. It answers the
//  three questions a brand-new user actually has — what is this, how
//  does it work, and is this private — and then gets out of the way.
//
//  Deliberately three pages and not six: onboarding is a toll booth
//  between the user and the app, and every extra page increases the
//  number of people who quit before reaching the content. Each page
//  makes exactly one point.
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the user finishes or skips.
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.17, blue: 0.29),
                         Color(red: 0.06, green: 0.10, blue: 0.19)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onFinish() } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            // Explicit padding inside the label, so the
                            // TAP TARGET grows rather than just the gap
                            // around a small one. Apple's minimum is 44×44
                            // points; a bare text button lands well under
                            // that and is genuinely hard to hit.
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    .accessibilityHint("Skips the introduction and opens the app")
                }

                TabView(selection: $page) {
                    OnboardingPage(
                        icon: { AnyView(CairnMark(size: 80)) },
                        title: "Track a spot over time",
                        message: "Pick a place on your body, a patch of skin or a healing scar, and photograph it whenever you like. Cairn Skin keeps every photo organized in its own timeline."
                    )
                    .tag(0)

                    OnboardingPage(
                        icon: { AnyView(
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 64))
                                .foregroundStyle(Color(red: 0.52, green: 0.84, blue: 0.84))
                                .accessibilityHidden(true)
                        )},
                        title: "Photos worth comparing",
                        message: "Your previous photo appears faintly over the camera so you can line up the same shot. Photos taken weeks apart are usually hard to compare, and matching the framing is what makes them worth putting side by side."
                    )
                    .tag(1)

                    OnboardingPage(
                        icon: { AnyView(
                            Image(systemName: "lock.shield")
                                .font(.system(size: 64))
                                .foregroundStyle(Color(red: 0.52, green: 0.84, blue: 0.84))
                                .accessibilityHidden(true)
                        )},
                        title: "Private by design",
                        message: "Photos never leave your iPhone. There's no account, no cloud, and nothing is sent anywhere. Face ID protects your photos automatically once you've saved your first one.\n\nCairn Skin is a wellness journal, not a medical tool. It doesn't diagnose anything, and for any health concern you should see a healthcare provider."
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                // A paged TabView is awkward under VoiceOver — swiping
                // moves between elements, not pages, so there's no obvious
                // way forward. The Continue button below works as the
                // linear path through, so make sure it's clearly labeled
                // and let VoiceOver users advance with it instead.
                .accessibilityLabel("Introduction, page \(page + 1) of 3")

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < 2 ? "Continue" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.42, green: 0.78, blue: 0.78), in: Capsule())
                        .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.19))
                }
                .accessibilityHint(page < 2
                                   ? "Goes to the next introduction page"
                                   : "Finishes the introduction and opens the app")
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

private struct OnboardingPage: View {
    let icon: () -> AnyView
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            icon()
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        // Read as one block by VoiceOver instead of three separate stops.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView {}
}
