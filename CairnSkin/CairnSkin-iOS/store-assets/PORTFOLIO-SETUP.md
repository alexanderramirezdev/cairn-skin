# Portfolio Setup, GitHub, Licensing, and Hosting

Everything needed to turn these projects into something an employer or client can actually look at, plus the free hosting that App Store Connect requires.

---

## 1. The MIT license (already added)

A `LICENSE` file with the MIT text now sits at the project root. Update the copyright year and name if needed.

**What it does and doesn't do, honestly:**

Publishing code publicly means anyone can copy it. That's true under any license. MIT doesn't prevent copying, what it does is signal that you understand open-source norms, which matters on a portfolio project. Code with *no* license defaults to "all rights reserved," which sounds protective but mostly reads as "didn't know to add one," and doesn't actually stop anyone.

**Why copying isn't the real risk here:** what makes this work valuable to an employer isn't the source. It's the commit history showing how you debugged it, and your ability to explain in an interview why the region-of-interest crop was necessary or why steadiness moved from image analysis to the gyroscope. Someone who forks the repo gets none of that, and gets exposed the moment they're asked a follow-up question.

GitHub also timestamps and attributes every commit to your account. Forks are publicly linked back to the original. That's a reasonable paper trail.

**If you'd rather not go fully public:** keep the repo private and add specific people (recruiters, hiring managers) as collaborators. You lose discoverability but keep full control. Plenty of people do exactly this.

*Not legal advice. For anything commercial where rights matter, talk to an attorney.*

---

## 2. Getting the repos on GitHub

Do this for both CairnSkin and ClearChart.

```bash
cd /path/to/CairnSkin

# Xcode build artifacts and local settings shouldn't be committed
cat > .gitignore << 'EOF'
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xcscmblueprint
*.xccheckout
.swiftpm/
Pods/
EOF

git init
git add .
git commit -m "Initial commit: Cairn Skin iOS app"
git branch -M main
```

Then create an empty repo on github.com (no README, no license, you have both), and:

```bash
git remote add origin https://github.com/YOURNAME/cairn-skin.git
git push -u origin main
```

**From here on, commit as you work rather than in one lump.** The commit history is a large part of what makes the repo worth showing, "fix: region-of-interest crop, background was dominating feature print comparison" tells a story that a single "initial commit" doesn't.

---

## 3. Hosting the privacy policy and support page

App Store Connect requires a **Privacy Policy URL** and a **Support URL**. GitHub Pages hosts both free, served over your own domain.

### Setup

1. In the `cairn-skin` repo: **Settings → Pages → Source: Deploy from a branch → main → /(root) → Save**. No separate site repo needed.

2. Add two files at the repo root:

`index.md`:
```markdown
# Cairn Skin

A private photo journal for tracking a spot on your skin over time.

## Support

Questions, bugs, or feedback: [support@ramirezlabs.app](mailto:support@ramirezlabs.app)

Typical response time: a few days.

## Privacy

See the [Privacy Policy](privacy).

## About

Cairn Skin is a wellness journaling tool. It does not diagnose, screen for, or assess any medical condition. For any health concern, consult a qualified healthcare provider.
```

`privacy.md`, paste in the contents of `store-assets/PRIVACY-POLICY.md`.

3. **Custom domain.** In Pages settings, set Custom domain to `cairnskin.ramirezlabs.app` (a subdomain keeps room for Quadrat and anything later). Then add a CNAME record in Cloudflare:

 - Type: `CNAME`, Name: `cairnskin`, Target: `YOURUSERNAME.github.io`
 - **Proxy status: DNS only**, Cloudflare's proxy interferes with GitHub's certificate provisioning

4. Wait for GitHub to issue the certificate (usually minutes), then tick **Enforce HTTPS**. Since `.app` is HSTS-preloaded, HTTPS isn't optional on this TLD, it has to work before the site loads at all.

5. Your URLs:
 - Support: `https://cairnskin.ramirezlabs.app/`
 - Privacy: `https://cairnskin.ramirezlabs.app/privacy`

Both go straight into App Store Connect.

### Without a custom domain

If you'd rather skip the DNS step, Pages still gives you `https://YOURUSERNAME.github.io/cairn-skin/` for free, and App Store Connect accepts it. The custom domain is polish, not a requirement.

## 4. Writing about the work

More valuable than the repos themselves, and most portfolios don't have it: a short post about a *specific* engineering problem, not a feature list.

The strongest candidate from this project is the **region-of-interest discovery**:

1. Two photos of the same forearm scored poorly against each other
2. Initial hypothesis: lighting changed
3. The screenshots showed the real cause, the backgrounds were completely different, and the arm occupied under half the frame
4. Vision's feature print describes the *whole image*; the app was measuring the room, not the skin
5. Fix: crop to the central region before extraction, plus an on-screen framing guide so users know where to aim
6. Measured result: same-subject distance dropped from 0.58 to 0.26

That's a real debugging narrative with evidence and a measurement at the end. It reads as engineering judgment rather than a feature announcement.

**A second good one:** why "hold steady" moved from image analysis to the gyroscope. The edge-energy metric scored a well-framed forearm *lower* than an out-of-frame keyboard, because skin is smooth and keyboards aren't, the metric was measuring subject texture, not focus. No threshold tuning fixes a signal that's wrong.

**On how the code was written:** AI-paired development is normal now, and being straightforward about it reads better than being vague. The framing that holds up: you owned the architecture, the testing, and the debugging. The bugs above were found by you, on a real device, from your own observations. Before using this professionally, make sure you can whiteboard those decisions cold, the risk isn't the tooling, it's being unable to explain a choice you shipped.

---

## 5. Suggested order

1. `.gitignore` and initial commits for both projects
2. GitHub Pages site live (unblocks App Store Connect)
3. First written post on the ROI crop
4. Second post when there's another good story
