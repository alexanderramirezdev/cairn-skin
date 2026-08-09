# App Store Connect — Listing Copy & Metadata

Draft text for the App Store listing, plus the App Privacy answers. Everything here is written to stay on the wellness side of the line — no "detect," "diagnose," "screen," "analyze your skin," or anything implying medical assessment.

---

## Name & subtitle

**App Name** (30 char max)
```
Cairn Skin
```

**Subtitle** (30 char max) — appears under the name in search results
```
Photo journal for your skin
```
Alternates if you want to test:
- `Track skin changes over time` (28)
- `Your private skin photo log` (27)

---

## Promotional text (170 char max)

Editable any time without a new build — good for seasonal or feature callouts.

```
Photograph the same spot over time and see how it changes. Guided framing keeps your photos comparable. Everything stays on your iPhone — no account, no cloud.
```

---

## Description (4000 char max)

```
Cairn Skin is a private photo journal for tracking a specific spot on your body over time — a patch of skin, a healing scar, an area you simply want to keep an eye on.

WHY IT'S DIFFERENT

Taking two comparable photos weeks apart is harder than it sounds. Lighting shifts, you stand a little closer, the angle changes — and suddenly the photos aren't really comparable at all.

Cairn Skin solves that. When you go to take a new photo, your previous one appears faintly over the camera view so you can line up the same framing. A live indicator tells you when the lighting is good and the phone is steady. The result is a series of photos that are actually worth comparing.

TRACK SEVERAL PLACES AT ONCE

Create a separate tracking area for each spot — "left forearm," "knee scar," "shoulder." Each one keeps its own baseline and its own history, so different places are never compared against each other.

SEE HOW MUCH HAS CHANGED

Every photo is compared against the first one in that area, showing how visually similar the two are. Once you have a few photos, a timeline shows how much things have shifted and when — with your photos alongside it, so you can see for yourself.

KEEP A RECORD

Add a note to any photo — a new product you started, how something felt that day. Export any area as a PDF with all your photos, dates, and notes, ready to save or bring to an appointment.

PRIVATE BY DESIGN

• Photos never leave your iPhone
• No account, no sign-up, no cloud
• No analytics, no tracking, no ads
• All image comparison happens on your device
• Face ID keeps your photos locked

A NOTE ON WHAT THIS IS

Cairn Skin is a wellness journal — a better way to keep and compare your own photos. It does not diagnose, screen for, or assess any medical condition, and the similarity percentages it shows are not medical measurements. They describe how visually alike two photographs are, nothing more. For any health concern, please see a qualified healthcare provider.
```

---

## Keywords (100 char max, comma-separated, no spaces)

Don't repeat words already in your name or subtitle — Apple indexes those separately.

```
photo,journal,log,tracker,progress,diary,timeline,compare,before,after,wellness,private,scar,healing
```
(97 characters)

**Deliberately avoided:** mole, melanoma, cancer, dermatology, diagnosis, detect, scan, check. These would pull the listing toward a medical claim and invite App Review scrutiny — and would attract users expecting something this app doesn't do.

---

## Category

- **Primary:** Health & Fitness
- **Secondary:** Lifestyle

---

## Age rating

Answer "None" to every content question. Expected result: **4+**.

---

## App Privacy answers ("nutrition label")

These are unusually simple because the honest answer is nothing:

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |

That single answer completes the section. If Apple asks follow-ups:
- No data used to track you
- No data linked to you
- No data collected

Photos stay in the app's sandboxed container and are never transmitted, which does not count as collection.

---

## URLs

Both required. GitHub Pages hosts them free — see PORTFOLIO-SETUP.md.

- **Privacy Policy URL:** required for all apps
- **Support URL:** required — can be a simple page with a contact email
- **Marketing URL:** optional

---

## Screenshots

Required sizes (Apple auto-scales down from the largest for most devices):

- **6.9" display** (iPhone 16 Pro Max / 15 Pro Max) — 1320 × 2868
- **6.5" display** (iPhone 11 Pro Max / XS Max) — 1242 × 2688

Up to 10 per size; 3–5 is plenty. Take them on device with Cmd+S in the simulator, or the physical device's screenshot then verify dimensions.

**Suggested sequence:**
1. **Guided capture with the ghost overlay** — this is the differentiator, lead with it
2. **Compare screen** showing baseline vs. current with the percentage
3. **Trend view** with the chart and thumbnail strip
4. **Home screen** with a few tracking areas
5. **Settings** showing the privacy options (reinforces the on-device story)

Use realistic-looking but non-identifying photos. Avoid anything that looks like a real medical condition — a reviewer seeing what appears to be a diagnosis use case may push back on the wellness framing.

---

## Review notes (message to App Review)

```
Cairn Skin is a personal wellness photo journal. Users photograph a chosen area over time and the app shows how visually similar each photo is to their first one, using Apple's Vision framework entirely on-device.

The app makes no medical claims. It does not diagnose, screen for, or assess any condition. The similarity percentage describes visual likeness between two photographs and is labeled as such throughout the app, including in exported PDFs.

No account is required. No data is collected or transmitted — all photos and comparison data remain in the app's local container.

To test: create a tracking area, take two photos (any subject works), then tap the second photo to see the comparison.
```

---

## Pre-submission checklist

- [ ] Deployment target set to iOS 17.0
- [ ] Mac and Apple Vision removed from Supported Destinations
- [ ] All four Info.plist usage descriptions present (Camera, Motion, Face ID)
- [ ] App icon set in Assets.xcassets
- [ ] Version and build numbers set
- [ ] Privacy policy live at a public URL
- [ ] Support page live at a public URL
- [ ] Screenshots captured at both required sizes
- [ ] Tested on a physical device, not just the simulator
- [ ] Debug tools confirmed absent from the Release build
- [ ] Enrolled in the App Store Small Business Program (15% vs 30% — it's a form)
