//
//  CairnSkinApp.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  The entry point for the iOS app. It owns the two shared objects the
//  whole app depends on (the photo store and the lock), and decides
//  whether to show content, a privacy cover, or the lock screen.
//

import SwiftUI

@main
struct CairnSkinApp: App {

    // One shared store for the whole app — every log entry (photo +
    // its extracted vector + metadata) lives here. A single source of
    // truth, injected down to every screen via .environment().
    @State private var store = TrackingStore()
    @State private var appLock = AppLock()

    // Persisted across launches — the onboarding shows exactly once.
    // @AppStorage is a UserDefaults-backed property wrapper.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @Environment(\.scenePhase) private var scenePhase

    /// Covers the screen while the app is inactive, so the snapshot iOS
    /// takes for the app switcher doesn't show anyone's photos.
    @State private var showPrivacyCover = false

    /// The lock only engages once there's something saved to protect —
    /// see AppLock.shouldLock(hasStoredPhotos:) for why.
    private var lockIsActive: Bool {
        appLock.shouldLock(hasStoredPhotos: !store.entries.isEmpty)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasSeenOnboarding {
                    // Onboarding outranks the lock: a first launch has no
                    // photos, so the lock isn't active anyway, and the
                    // introduction should be the very first thing seen.
                    OnboardingView {
                        hasSeenOnboarding = true
                    }
                } else if !lockIsActive || appLock.isUnlocked {
                    HomeView()
                } else {
                    LockScreenView(
                        appLock: appLock,
                        onUnlock: { await appLock.authenticate() },
                        onPasscode: { await appLock.authenticateWithPasscode() }
                    )
                }

                // The privacy cover sits on top of everything while the
                // app is inactive. It is NOT the lock screen — dismissing
                // it requires no authentication, because .inactive is a
                // routine state, not an exit.
                if showPrivacyCover {
                    PrivacyCoverView()
                        .transition(.opacity)
                }
            }
            .environment(store)
            .environment(appLock)
            // ".task(id:)" rather than ".task" — this is the fix for a
            // stuck lock screen.
            //
            // A plain .task runs once, when the view appears. On a cold
            // launch that can happen while the scene is still .inactive,
            // so the "is it active yet?" guard rejected it and no prompt
            // fired. .onChange didn't save it either: if the scene was
            // already .active by the time the view existed, there's no
            // CHANGE to observe, so nothing fired at all and the user sat
            // on a spinner until they force-quit.
            //
            // .task(id:) runs on first appearance AND again every time
            // the id changes, so cold launch and return-from-background
            // both funnel through one path.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }

                if lockIsActive && !appLock.isUnlocked && !appLock.hasPromptedSinceLock {
                    await appLock.authenticate()
                } else if !lockIsActive {
                    // Nothing saved yet, so nothing to protect. Marking the
                    // session unlocked here stops the first saved photo from
                    // flipping lockIsActive mid-session and dropping a lock
                    // screen on someone actively using the app.
                    appLock.isUnlocked = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {

                case .inactive:
                    // IMPORTANT: do NOT re-lock here.
                    //
                    // ".inactive" is far broader than "the user left the
                    // app." It also fires for system permission dialogs,
                    // presenting the camera, pulling down Control Center,
                    // and — critically — the Face ID prompt itself. Locking
                    // on .inactive meant taking your first photo triggered
                    // the camera dialog, which fired .inactive, which locked
                    // the app the moment the photo saved. It could also
                    // deadlock: authenticating fires .inactive, which locks,
                    // which prompts authentication again.
                    //
                    // So .inactive only hides content from the app-switcher
                    // snapshot. Authentication is untouched.
                    showPrivacyCover = true

                case .active:
                    // Authentication is NOT triggered here — the
                    // .task(id: scenePhase) above handles it, and doing it
                    // in both places would race and double-prompt.
                    showPrivacyCover = false

                case .background:
                    // A real exit. This is where re-authentication belongs.
                    showPrivacyCover = true
                    appLock.lock()

                @unknown default:
                    break
                }
            }
        }
    }
}

/// Shown while the app is inactive so the app-switcher snapshot doesn't
/// leak photos. Uses the same treatment as the lock screen — a plain
/// system icon on white read as a broken loading state rather than an
/// intentional privacy screen.
private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.17, blue: 0.29),
                         Color(red: 0.06, green: 0.10, blue: 0.19)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                CairnMark(size: 76)
                Text("Cairn Skin")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
