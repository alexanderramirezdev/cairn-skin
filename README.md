# Cairn Skin

A photo-based wellness tracking app: create a tracking area for each spot
you want to follow (a forearm, a knee scar, a shoulder), log photos over
time, and see an on-device "visual similarity" comparison against that
area's first photo. Each area keeps its own baseline and history, so
different body locations are never compared against each other.

This is genuinely a **wellness** app: it logs, compares, and visualizes.
It does not diagnose, screen, or make clinical claims, and it's built to
stay that way (see "Staying honest about scope" below). Lessons learned
here (what real day-to-day use looks like, how well the on-device vector
comparison performs) are meant to inform the separate, properly regulated
diagnostic pathway later, and a future standalone iOS ClearChart app. Neither of those is attempted here.

---

## 1. What's in this project

| File | What it is |
|---|---|
| `CairnSkinApp.swift` | App entry point |
| `Models/TrackingEntry.swift` | Data shape for one logged photo (category, date, file references) |
| `Vision/FeatureExtractor.swift` | The on-device "AI": turns a photo into a comparable vector using Apple's Vision framework |
| `Store/TrackingStore.swift` | Local storage: saves/loads photos, vectors, and the entry index to disk |
| `Views/CameraPicker.swift` | SwiftUI wrapper around the camera |
| `Views/HomeView.swift` | Category selection screen |
| `Views/TimelineView.swift` | Photo history for one category, add-photo button |
| `Views/CompareView.swift` | Baseline vs. selected photo, with the similarity result and notes |
| `Views/AddNoteView.swift` | Optional note sheet shown right after capture |
| `Views/TrendView.swift` | Change-over-time chart with paired thumbnails |
| `Views/SettingsView.swift` | Biometric lock toggle |
| `Views/ShareSheet.swift` | System share sheet wrapper for PDF export |
| `Views/OnboardingView.swift` | Three-page first-launch introduction |
| `Store/DebugDataGenerator.swift` | DEBUG-only bulk test data generator |
| `Store/AppLock.swift` | Face ID / Touch ID gating, no account required |
| `Store/PhotoArchive.swift` | All disk reading and writing, usable from any thread |
| `Store/ReportGenerator.swift` | Builds the PDF photo log |
| `Views/GuidedCaptureView.swift` | **The differentiator.** Live camera with a ghost overlay of your last photo plus real-time lighting/sharpness badges |
| `Camera/CameraSessionController.swift` | Manages the live AVFoundation camera session and feeds frames to the analyzer |
| `Camera/CameraPreviewView.swift` | SwiftUI bridge for displaying the live camera feed |
| `Vision/FrameQualityAnalyzer.swift` | Scores each live frame for brightness |
| `Camera/MotionMonitor.swift` | Gyroscope-based steadiness detection |
| `Models/TrackingArea.swift` | A named body location with its own baseline and history |

Suggested reading order: `BaselineApp` → `TrackingEntry` → `FeatureExtractor` → `TrackingStore` → `HomeView` → `TimelineView` → `CameraPicker` → `CompareView`.

---

## 2. How the core tech works (plain English)

1. **Capture.** User takes a photo with the in-app camera.
2. **Extract.** `FeatureExtractor` runs Apple's `VNGenerateImageFeaturePrintRequest` on it, entirely on-device, no network call. This turns the photo into a compact numeric fingerprint (a "feature print") that captures its abstract shapes/textures/structure rather than raw pixels. Raw pixel comparison would be thrown off by small lighting or angle changes between photos taken days apart; the feature print is far more robust to that.
3. **Store.** The photo (JPEG) and its feature print are saved to the app's private on-device storage. Nothing leaves the phone.
4. **Compare.** When viewing a photo, the app loads the saved feature print for that photo and for the category's very first ("baseline") photo, and calls Apple's built-in `computeDistance(to:)`, Apple has already implemented the vector math, so the app doesn't need a custom similarity algorithm.
5. **Display.** The distance is converted into a rough 0-100% "visual similarity" figure and shown with a disclaimer.

This is the free, fully on-device equivalent of a heavier "MobileNet → 1024-dim vector → cosine similarity" pipeline, Apple's Vision framework does the same essential job without any third-party model or cloud dependency.

---

## 2.5 The differentiator: guided capture

The single most common complaint about apps in this category (skin/wound photo trackers) is that taking two genuinely comparable photos, same distance, same angle, same lighting, days or weeks apart is much harder than it sounds, and inconsistent photos quietly wreck the comparison feature that's the whole point of the app.

`GuidedCaptureView` addresses this directly with two live signals, both running on real AVFoundation camera frames, not just at the moment of capture:

1. **Ghost overlay.** Your previous photo in that category is drawn semi-transparent directly on top of the live camera feed, so you can visually line up position and distance before shooting, the same idea photographers use for match-cut composition.
2. **Live quality badges.** `FrameQualityAnalyzer` scores every few frames for brightness (via Core Image's `CIAreaAverage`) and a rough sharpness/blur signal (via a Laplacian edge-detection convolution). Badges update in real time so you know before you shoot, not after.

**Be honest with yourself about the sharpness metric before you ship it.**It's a heuristic, edge energy is a reasonable proxy for "is this in focus," not a calibrated measurement. Test it against your own real photos (different lighting, different subjects) and adjust the threshold in `FrameQualityAnalyzer.isSharp` if it's flagging good photos as blurry or vice versa.

The guidance never blocks the shutter, badges inform, they don't gate. Someone photographing an awkward body location or dealing with unusual lighting still needs to be able to just take the photo.

### Macro focus and camera selection (learned the hard way, twice)

Close-up shots came out blurry on an iPhone 17 Pro Max, which definitely supports macro. The cause was the camera selection line: requesting `.builtInWideAngleCamera` by name pins the session to the main lens and **opts out of iOS's automatic macro switching**. Macro works by switching to an autofocusing ultra-wide lens, and iOS only does that when the session is bound to a *virtual* device that owns multiple lenses.

The fix is a discovery session preferring `.builtInTripleCamera`, then `.builtInDualWideCamera`, and only falling back to `.builtInWideAngleCamera` on hardware with a single lens.

**The second half of the problem isn't fixable in software.** Base iPhones have a fixed-focus ultra-wide, and iPhone Air has no ultra-wide at all. Those devices physically cannot focus closer than roughly 10cm. `minimumFocusDistance` reports this per-device, so the capture screen detects it and tells those users the actual workaround: stand back and use the zoom presets to fill the framing box. Without that hint, people keep moving closer and getting blurrier results with no idea why.

Zoom is capped at 5× because beyond that it's pure digital upscaling. Interpolated pixels would quietly degrade the feature-print comparison the whole app rests on. Tap-to-focus is also available, since a skin patch filling the frame gives centre-weighted autofocus very little contrast to lock onto.

### The region-of-interest crop (learned the hard way)

Early real-device testing produced a surprising result: two photos of the same forearm scored poorly against each other, while the tester assumed only lighting had changed. Looking at the actual images, the background had changed completely (dark clothing in one, a laptop and wood floor in the other) and the arm occupied under half the frame.

The cause: Vision's feature print describes the *whole image*. It has no concept of a "subject." With most of the frame given over to background, the app was largely measuring the room rather than the skin.

The fix is `FeatureExtractor.cropToRegionOfInterest`, which discards everything outside the central 60% square before generating the feature print, paired with a dashed framing box in `GuidedCaptureView` so users know where to place the subject. This single change matters more for real-world accuracy than any threshold tuning elsewhere in the codebase.

**Note on existing data:** feature prints generated before this crop was added are not comparable to ones generated after. If you have test entries from an earlier build, delete and recapture them.

---

## 3. Renaming an existing project

If you already have this building under an older name, you don't need a new project, rename in place:

1. **App struct file:** it's now `CairnSkinApp.swift`. Delete the old file's reference from Xcode's navigator and add this one.
2. **Xcode target:** click the project icon → slow double-click the target name in the sidebar → type `CairnSkin` (no space, target/module names can't contain spaces). Accept Xcode's offer to rename related items.
3. **Display Name:** target → General → **Display Name** → `Cairn Skin`. *This* is what appears under the Home Screen icon, and it can contain a space.
4. **Bundle identifier:** target → Signing & Capabilities → `com.yourname.cairnskin`. Note: changing this makes iOS treat it as a brand-new app, so existing test photos won't carry over. Leave it unchanged if you want to keep your test data for now.
5. **App icon:** copy the `AppIcon.appiconset` folder from this project's `Assets.xcassets` into your existing one.

## 4. Setting up the project in Xcode (from scratch)

1. Xcode → **File → New → Project… → iOS → App**.
2. Product Name: `Baseline`. Interface: **SwiftUI**. Storage: none (we're using our own file-based store, not CoreData/SwiftData).
3. Delete the generated `ContentView.swift`.
4. Drag this folder's `Baseline/` contents into the project navigator (Models, Store, Views, Vision folders and the root .swift files), checking "Copy items if needed."
5. Build (Cmd+B).

### Required Info.plist keys

Both are needed or the app crashes when the capture screen opens:

1. Project → **Baseline target** → **Info** tab.
2. Add `Privacy - Camera Usage Description` → `Baseline uses the camera to log tracking photos.`
3. Add `Privacy - Motion Usage Description` → `Baseline uses motion data to tell you when the phone is steady enough for a clear photo.`

### Minimum iOS version

Set the deployment target to **iOS 17.0 or later** (project → target → General → Minimum Deployments). The app pins Vision's feature print algorithm to revision 2, which requires iOS 17, this pinning is deliberate: it keeps every stored photo vector comparable with every other one forever, even across future iOS updates (different algorithm revisions produce incompatible vectors).

### Simulator note

The iOS Simulator has **no real camera**. The app detects this automatically: `TimelineView` checks `UIImagePickerController.isSourceTypeAvailable(.camera)` and routes to the plain photo-library picker (`CameraPicker`) instead of the live guided-capture screen when no camera exists. On a real device you'll always get the full `GuidedCaptureView` experience with the ghost overlay and live badges.

---

## 5. Running it

1. Choose an iPhone simulator (or your own device) in the toolbar.
2. Cmd+R.
3. Tap a category → tap the camera button → take/pick a photo. It processes for under a second and appears in the timeline.
4. Add a second photo to the same category on a different day (or just tap the button twice for testing) → tap it → see the similarity comparison against your first photo.

---

## 5.5 Trend view and PDF export, the design constraints

**The trend chart shows magnitude of change, never direction, and never whether change is good or bad.** The metric cannot support that claim: a rash clearing up and a mole growing both register as "more different from baseline." The app has no way to tell improvement from deterioration, and a chart implying otherwise would be the most misleading thing in the product, precisely because someone with a real concern would read a falling line as reassurance. So the language is about *how much* and *when*, and every point is paired with its thumbnail so the user's own eyes make the judgment they're far better equipped to make.

The y-axis is deliberately labeled "Similar" to "Different" rather than with numbers. A precise-looking axis would invite reading the chart as a measurement with units.

**The PDF carries the disclaimer on page one and in every page footer.** A PDF outlives the screen that made it, it gets emailed, printed, and read by people who never saw the app. Whatever framing the file carries is the only framing a reader gets.

**There is no "email this" button, on purpose.** The app writes a file and hands it to the system share sheet; where it goes is the user's decision. Building a send path would make the app a channel for transmitting health-adjacent photos, a materially different privacy posture than "nothing leaves your device unless you choose."

**Locking happens on `.background`, not `.inactive`.** This distinction caused a real bug worth remembering: `.inactive` fires for far more than "the user left the app", it also fires for system permission dialogs, presenting the camera, pulling down Control Center, and the Face ID prompt itself. Locking on `.inactive` meant taking the first photo triggered the camera dialog, fired `.inactive`, and locked the app the instant the photo saved. It can also deadlock, since authenticating fires `.inactive`, which locks, which prompts authentication again. The fix is two-tier: `.inactive` shows an opaque privacy cover (so the app-switcher snapshot doesn't leak photos) and requires no authentication to dismiss, while `.background`, an actual exit, is what re-locks.

**The lock is on by default, but only engages once there's a photo saved.** Most people never go looking for a privacy setting, and body photos should be protected without having to ask. But prompting for Face ID on a blank first launch, before the user has seen a screen or has anything worth protecting, is a confusing first impression, and some people deny the permission reflexively when it appears without context. So the lock is enabled by default and activates the moment the first photo exists. (Implementation note: `UserDefaults.object(forKey:)` rather than `bool(forKey:)`, since `bool()` can't distinguish "never set" from "deliberately turned off.")

**The lock is biometric, not an account.** An account would mean a server, a password store, and a user record tying a real identity to body photos, strictly worse than today's position. Sign in with Apple doesn't avoid this: it proves identity, but you still need a backend to receive the result. `LocalAuthentication` protects photos already on the device with no infrastructure at all. Authentication and sync are separate problems; a login only becomes necessary when data must follow a user across devices. (If that day comes, CloudKit private database keeps the data in the user's own iCloud rather than on your server.)

---

## 6. Staying honest about scope (read this before adding features)

This app is designed to stay a wellness tool, not slide into being an undisclosed diagnostic tool. A few guardrails already built in, and why they matter:

- **The disclaimer travels with the number.** Every place the similarity percentage appears on screen, the "not a medical measurement" disclaimer appears right below it (`CompareView.swift`). Don't let the number get surfaced anywhere without that context attached, widgets, notifications, share sheets, exports, etc.
- **Wording matters as much as function.** Keep in-app copy, App Store description, and category names in wellness language ("track," "visualize," "trend") rather than clinical language ("diagnose," "screen," "detect"). The `TrackingCategory.captureGuidance` strings are a template for this tone.
- **The similarity percentage is uncalibrated.** `FeatureExtractor.similarityPercent(forDistance:)` uses a rough placeholder threshold. Before shipping, test it against a real set of photos in each category and adjust, but calibrating it better doesn't change its status as a wellness trend indicator, not a clinical score.
- **Local-only storage, on purpose.** No cloud sync in this version. If you add sync later (even just for backup), treat that decision deliberately, don't let it happen as a side effect of adding some other feature.

---

## 6.5 First-launch, data deletion, and details toggle

**Onboarding** shows exactly once (tracked via `@AppStorage("hasSeenOnboarding")`), is three pages by design, what it is, how it works, that it's private, and is skippable. It outranks the lock screen in the app entry's view hierarchy because a first launch has no photos and therefore no active lock.

**Delete All Data** lives in Settings behind a confirmation dialog that names the consequence. It removes every area, entry, photo, and vector. Privacy-conscious users expect a full-wipe option in a photo app, and it's a reasonable App Review question to be able to answer "yes" to.

**Show comparison details** (Settings) surfaces the raw feature-print distance on the compare screen. It replaced the dev-only calibration flag, same number, now a legitimate power-user option, and still the tool for tuning `noiseFloor` / `notComparableThreshold` against real measurements.

**Deleting the baseline photo** is allowed (from the compare screen's trash button), and the confirmation explains what happens: the next-oldest photo becomes the new baseline and comparisons re-anchor to it.

## 6.6 Volume testing

`Store/DebugDataGenerator.swift` (Settings → Debug Tools, DEBUG builds only) bulk-generates synthetic entries so performance problems that only appear at scale can be found in a minute rather than over months of real use.

The generated images are skin-toned gradients with speckling that drifts gradually across the series, not random noise, random images produce meaningless feature-print distances and don't exercise the comparison path realistically. A deterministic seeded PRNG makes runs reproducible so results stay comparable between tests.

Try 30 entries to see whether the trend view slows (it loads feature prints sequentially), and 100+ to stress PDF export (it renders every photo into a page). The whole file is wrapped in `#if DEBUG` so it cannot ship by accident.

## 6.7 Store and portfolio assets

`store-assets/` holds everything needed outside the code:

- **`PRIVACY-POLICY.md`**, ready to host; the honest version is short because nothing leaves the device
- **`APP-STORE-LISTING.md`**, name, subtitle, description, keywords, App Privacy answers, screenshot plan, and a note to App Review. All written to stay on the wellness side of the line; the keyword list deliberately excludes *mole, melanoma, dermatology, detect, scan*
- **`PORTFOLIO-SETUP.md`**, GitHub setup, MIT licensing rationale, free GitHub Pages hosting for the two URLs App Store Connect requires, and notes on writing about the work

## 6.8 Concurrency: why disk access is a separate type

`TrackingStore` owns the areas and entries arrays that drive every screen, so it belongs on the main actor. But it originally also read photos and vectors off disk, which is stateless and perfectly safe from a background thread.

That mix caused trouble as soon as real background work appeared. Trend calculation and PDF export both run in `Task.detached` (they were freezing the UI otherwise), and both kept colliding with main-actor isolation. Marking individual methods `nonisolated` looked like a fix but wasn't: those methods still reached into main-actor-isolated stored properties like the thumbnail cache, so the compiler was right to complain.

`PhotoArchive` resolves it structurally. It holds no main-actor state, so it needs no annotations to be usable anywhere, and background tasks take it directly. The pattern at every call site is the same: gather what's needed on the main actor (a plain array of value types, plus the archive), then hand only those across the boundary. The store never crosses it.

Worth remembering as a general rule: when concurrency annotations start piling up on individual members, the type is usually doing two jobs and wants splitting.

## 6.9 Live URLs

| What | Where |
|---|---|
| Studio site | `https://ramirezlabs.app` |
| Support page | `https://ramirezlabs.app/cairnskin/` |
| Privacy policy | `https://ramirezlabs.app/cairnskin/privacy` |
| Support email | `support@ramirezlabs.app` |

The support email and privacy policy are also linked from Settings inside the app, alongside the version and build number, which is the first thing worth knowing from a bug report.

The privacy policy exists in two places: `store-assets/PRIVACY-POLICY.md` here is the source of record, and `cairnskin/privacy.html` in the `ramirezlabs-site` repo is what's actually served. Edit both when it changes.

## 7. Branding

**Name:** Cairn Skin. A cairn is the stack of stones hikers leave to mark a spot on a trail so they can find their way back to it, which is close to exactly what this app does: you leave a marker at a specific place so you can return later and see where things stand relative to it. "Skin" carries the category, which helps App Store search since people search for what a thing does.

*Why not "Baseline":* it was the first choice, and a USPTO search killed it. "Baseline" is heavily crowded in health and wellness software specifically, including PROJECT BASELINE (Verily/Alphabet, registered Class 9 for healthcare software), a Class 9 filing for health-information mobile apps, and a Class 3 registration for skin moisturizer. Adding "Skin" wouldn't have helped: in likelihood-of-confusion analysis, tacking a descriptive word onto someone else's mark carries little weight. The lesson generalizes, "Baseline" is a natural word for anything measuring change over time, so everyone in this space had already reached for it. Distinctive names are both easier to clear and easier to protect.

A search for "cairn" alone returned 16 live marks total (versus 4,579 for "baseline"), with none in skin, dermatology, photo tracking, or wellness journaling. Two worth an attorney's eye eventually: CAIRN (FitClimb, Class 9, a wilderness-safety app, same class, different product) and CAIRN DIAGNOSTICS (Class 44, breath-test kits, more relevant to a future regulated product than to this one).

**Icon:** four balanced stones, slightly rotated and offset so they read as real rocks rather than a diagram, with the teal capstone on top. The newest stone sits on the accumulated history beneath it, which is the app's mechanic in miniature. Deliberately avoids medical crosses, red palettes, and body imagery, all of which would signal a clinical product.

**Still to do before relying on the name:** this is pattern-reading from a public database, not a legal opinion. A clearance search from a trademark attorney (typically $300-500) is cheap insurance before investing in marketing or filing an application of your own.

Source files for the icon, including small-size previews, are in `icon-source/`.

## 8. Where this goes next (not part of this build)

- **Learning phase:** ship this, gather real usage data on capture consistency, how people actually use the two categories, and how the similarity metric holds up against real day-to-day photos (lighting, angle drift, etc.).
- **Standalone iOS ClearChart:** a separate app, broadening ClearChart's reach beyond Vision Pro to iPhone, built from what's learned about clinical documentation needs, a distinct project from this one and from the diagnostic pathway below.
- **Diagnostic pathway (Phase 2):** a *separate app*, built from day one as a regulated medical device: cloud vector database (HIPAA-eligible), a medical-grade vision model trained on clinical datasets, FDA Software-as-a-Medical-Device classification, and clinical validation before any diagnostic claim is made. It does not reuse this app's binary or its "wellness" framing, it is declared for what it is from the start.
