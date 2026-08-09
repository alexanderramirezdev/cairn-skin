//
//  AppLock.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Face ID / Touch ID gating for the whole app, with the device
//  passcode as automatic fallback.
//
//  WHY LOCAL BIOMETRICS AND NOT A LOGIN ACCOUNT:
//  An account would require a server, a password store, and a user
//  record tying a real identity to body photos — which is a strictly
//  worse privacy position than the app has today. Sign in with Apple
//  doesn't avoid this either: it proves identity, but you still need a
//  backend to receive and store the result.
//
//  What's actually needed here is protecting photos already on the
//  device, and LocalAuthentication does that with no infrastructure at
//  all. Authentication and sync are separate problems; a login only
//  becomes necessary when data has to follow a user across devices.
//
//  The lock re-engages when the app leaves the foreground, so handing
//  someone an unlocked phone doesn't hand them the photo history.
//

import LocalAuthentication
import SwiftUI
import Observation

@Observable
final class AppLock {

    /// True once the user has authenticated for this foreground session.
    var isUnlocked = false

    /// Set when authentication fails, so the UI can offer a retry.
    var lastError: String?

    /// Turned on/off by the user in Settings. When off, the app opens
    /// straight to content — appropriate for someone tracking something
    /// non-sensitive who finds a lock screen annoying.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            // Turning the lock off should take effect immediately rather
            // than at next launch.
            if !isEnabled { isUnlocked = true }
        }
    }

    private static let enabledKey = "appLockEnabled"

    init() {
        // Default ON. Most people won't think to go looking for a privacy
        // setting, and photos of your own body are exactly the kind of
        // thing that should be protected without having to ask for it.
        //
        // "object(forKey:)" rather than "bool(forKey:)" matters here:
        // bool() returns false for a key that was never set, which would
        // make "never touched the setting" indistinguishable from
        // "deliberately turned it off." Checking for nil first lets a
        // brand-new install default to true while still respecting a user
        // who explicitly switched it off.
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        self.isUnlocked = !isEnabled
    }

    /// Whether the lock should actually engage right now.
    ///
    /// Enabled-but-nothing-saved deliberately does NOT lock. Prompting
    /// for Face ID before someone has seen a single screen — or has any
    /// data worth protecting — is a confusing first impression, and some
    /// people deny the permission reflexively when it appears without
    /// context. Once the first photo exists there's something real to
    /// protect, and the lock takes over from then on without the user
    /// ever having to find a setting.
    func shouldLock(hasStoredPhotos: Bool) -> Bool {
        isEnabled && hasStoredPhotos
    }

    /// Whether this device can do biometrics at all. Used to hide the
    /// setting on devices where it would never work.
    var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Human-readable name for whatever this device uses, so the UI can
    /// say "Face ID" instead of a generic "biometrics".
    var biometryName: String {
        let context = LAContext()
        // biometryType is only populated AFTER canEvaluatePolicy runs —
        // reading it on a fresh context returns .none regardless of the
        // hardware.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// DIAGNOSTIC: describes exactly what the system reports about
    /// biometrics on this device, including why they're unavailable.
    /// Surfaced in Settings so a "why is it asking for my passcode?"
    /// question has an answer instead of a guess.
    var biometryDiagnostic: String {
        let context = LAContext()
        var error: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error
        )

        if canUseBiometrics {
            return "\(biometryName) is available."
        }

        guard let code = error.map({ LAError.Code(rawValue: $0.code) }) ?? nil else {
            return "Biometrics unavailable for an unknown reason."
        }

        switch code {
        case .biometryNotEnrolled:
            return "No face or fingerprint is enrolled on this device. Set one up in Settings."
        case .biometryNotAvailable:
            // The usual cause is a missing NSFaceIDUsageDescription key,
            // or the user denying Face ID for this app.
            return "Biometrics are unavailable to this app. Check Settings > Face ID & Passcode > Other Apps, and confirm the app has a Face ID usage description."
        case .biometryLockout:
            return "Too many failed attempts. Unlock your device with its passcode once to re-enable biometrics."
        case .passcodeNotSet:
            return "No device passcode is set, so there's nothing to authenticate against."
        default:
            return "Biometrics unavailable (\(code.rawValue))."
        }
    }

    @MainActor
    func authenticate() async {
        guard isEnabled else {
            isUnlocked = true
            return
        }

        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        hasPromptedSinceLock = true
        let context = LAContext()

        // Hide the "Enter Password" button on the first prompt. Without
        // this, iOS shows a fallback option immediately, and a single
        // mis-scan sends the user straight to the passcode keypad.
        context.localizedFallbackTitle = ""

        // Try BIOMETRICS FIRST, explicitly. The combined
        // ".deviceOwnerAuthentication" policy jumps straight to the
        // passcode keypad whenever biometrics aren't immediately usable,
        // which makes a misconfiguration look like normal behavior.
        var biometricError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Unlock to view your tracking photos"
                )
                if success {
                    isUnlocked = true
                    lastError = nil
                    return
                }
                lastError = "\(biometryName) didn't recognize you."
            } catch {
                // Stop here rather than auto-escalating to the passcode
                // keypad. A cancelled or failed scan should return the
                // user to the lock screen with clear options, not shove
                // an unexpected keypad in front of them.
                lastError = friendlyMessage(for: error)
            }
            return
        }

        // Biometrics unusable on this device at all (not enrolled, denied,
        // locked out). Report why, and let the user choose the passcode
        // from the lock screen rather than forcing it.
        if let biometricError {
            lastError = friendlyMessage(for: biometricError)
        } else {
            lastError = "\(biometryName) isn't available. Use your passcode instead."
        }
    }

    /// Authenticate with the device passcode. The explicit escape hatch,
    /// offered on the lock screen rather than triggered automatically.
    @MainActor
    func authenticateWithPasscode() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        hasPromptedSinceLock = true
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No device passcode set — nothing to authenticate against,
            // so don't strand the user outside their own photos.
            isUnlocked = true
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock to view your tracking photos"
            )
            isUnlocked = success
            lastError = success ? nil : "Couldn't verify it's you."
        } catch {
            lastError = friendlyMessage(for: error)
        }
    }

    /// Turns an authentication error into something a person can act on.
    /// Users should never see a raw NSError string — "com.apple
    /// .LocalAuthentication error 6" tells them nothing about what to do
    /// next, and reads as a broken app rather than a locked one.
    private func friendlyMessage(for error: Error) -> String? {
        let code: LAError.Code?
        if let laError = error as? LAError {
            code = laError.code
        } else if let nsError = error as NSError?, nsError.domain == LAErrorDomain {
            code = LAError.Code(rawValue: nsError.code)
        } else {
            code = nil
        }

        switch code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            // Deliberate dismissal or a system interruption. Showing an
            // error for something the user chose is just noise.
            return nil
        case .authenticationFailed:
            return "\(biometryName) didn't recognize you."
        case .biometryNotEnrolled:
            return "No face or fingerprint is set up on this device."
        case .biometryNotAvailable:
            return "\(biometryName) isn't available right now."
        case .biometryLockout:
            return "Too many attempts. Use your passcode to unlock."
        case .passcodeNotSet:
            return "This device has no passcode set."
        default:
            return "Couldn't verify it's you."
        }
    }

    /// Whether an authentication prompt has already been shown since the
    /// app last locked. Prevents re-prompting in a loop after the user
    /// cancels — one automatic attempt per lock, then it's their move.
    var hasPromptedSinceLock = false

    /// True while a prompt is on screen. Guards against two triggers
    /// firing at once (launch .task and a .active transition, say) and
    /// stacking two Face ID dialogs.
    private(set) var isAuthenticating = false

    /// Called when the app leaves the foreground.
    func lock() {
        guard isEnabled else { return }
        isUnlocked = false
        hasPromptedSinceLock = false   // next foreground gets a fresh auto-prompt
        lastError = nil
    }
}

/// The screen shown while locked.
///
/// It authenticates AUTOMATICALLY when it appears — the user shouldn't
/// have to tap a button to start a face scan any more than they do on
/// the iOS lock screen itself. Buttons appear only after an attempt has
/// already run.
struct LockScreenView: View {
    let appLock: AppLock
    let onUnlock: () async -> Void
    let onPasscode: () async -> Void

    var body: some View {
        ZStack {
            // Matches the app icon's palette so the lock screen reads as
            // part of Cairn Skin, not a system error page.
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.17, blue: 0.29),
                         Color(red: 0.06, green: 0.10, blue: 0.19)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                CairnMark(size: 88)
                    .padding(.bottom, 28)

                Text("Cairn Skin")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Locked")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)

                // Reserve space so the layout doesn't jump when a message
                // appears or the buttons swap in.
                Group {
                    if let error = appLock.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)
                    }
                }
                .frame(height: 40)
                .padding(.top, 20)

                if appLock.hasPromptedSinceLock {
                    VStack(spacing: 14) {
                        Button {
                            Task { await onUnlock() }
                        } label: {
                            Label("Try \(appLock.biometryName)", systemImage: "faceid")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.42, green: 0.78, blue: 0.78),
                                            in: Capsule())
                                .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.19))
                        }

                        Button {
                            Task { await onPasscode() }
                        } label: {
                            Text("Use Passcode")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 48)
                    .transition(.opacity)
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .frame(height: 96)
                }

                Spacer()
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appLock.hasPromptedSinceLock)
        // NOTE: authentication is deliberately NOT triggered from this
        // view's .task.
        //
        // This view appears the instant lock() runs, which happens while
        // the app is moving to the background. A .task here fired Face ID
        // on the way out — the user saw a scan prompt appear as they left
        // the app, it failed (you can't authenticate a backgrounding app),
        // and that failure consumed the one auto-prompt, stranding them on
        // an error screen when they came back.
        //
        // CairnSkinApp triggers authentication instead, and only when the
        // scene is genuinely .active.
    }
}

/// The stacked-stones mark from the app icon, drawn in SwiftUI so it can
/// be reused at any size without shipping extra image assets.
struct CairnMark: View {
    var size: CGFloat = 88

    private let stones: [(w: CGFloat, h: CGFloat, dx: CGFloat, rot: Double, color: Color)] = [
        (1.00, 0.34, -0.02, -3, Color(red: 0.34, green: 0.39, blue: 0.51)),
        (0.78, 0.30,  0.04,  4, Color(red: 0.42, green: 0.49, blue: 0.61)),
        (0.57, 0.27, -0.04, -5, Color(red: 0.89, green: 0.93, blue: 0.96)),
        (0.37, 0.20,  0.02,  3, Color(red: 0.52, green: 0.84, blue: 0.84)),
    ]

    var body: some View {
        VStack(spacing: -size * 0.04) {
            // Drawn top-down so the smallest stone sits on top.
            ForEach(Array(stones.enumerated().reversed()), id: \.offset) { _, stone in
                Ellipse()
                    .fill(stone.color)
                    .frame(width: size * stone.w, height: size * stone.h)
                    .rotationEffect(.degrees(stone.rot))
                    .offset(x: size * stone.dx)
            }
        }
        .frame(width: size, height: size * 1.05)
    }
}
