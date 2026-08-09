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
            .task {
                // Only prompt if the scene is actually active. On a cold
                // launch scenePhase is .active by the time this runs; if
                // the app was launched into the background for any reason,
                // this correctly does nothing and the .active transition
                // below picks it up instead.
                if lockIsActive && !appLock.isUnlocked && scenePhase == .active {
                    await appLock.authenticate()
                } else if !lockIsActive {
                    // Mark the session unlocked even though we skipped
                    // authentication. Without this, saving the very first
                    // photo would flip lockIsActive to true mid-session
                    // and drop a lock screen on someone actively using
                    // the app.
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
                    showPrivacyCover = false
                    // THE ONLY place automatic authentication is triggered
                    // on return. It must be here rather than in
                    // LockScreenView's .task: that view appears the moment
                    // lock() runs, which is during backgrounding, so a task
                    // there fired Face ID on the way OUT of the app — it
                    // failed, consumed the single auto-prompt, and left the
                    // user stranded on an error when they came back.
                    if lockIsActive && !appLock.isUnlocked && !appLock.hasPromptedSinceLock {
                        Task { await appLock.authenticate() }
                    }

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
