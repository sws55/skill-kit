---
name: two-app-setup
description: Set up, or audit, the two-app split — a Metro-connected dev variant living beside a standalone distribution build on the same phone. Use when starting this pattern in a project that does not have it, porting it from another repo, or checking an existing config against the traps that fail silently ("did we get the channel right", "why does the standalone build show the dev-launcher screen", "will an OTA reach the build we shipped").
---

# Two-app setup

Two builds of one codebase, installed side by side: a **dev variant** wired to Metro, and a
**distribution variant** that behaves the way a tester's phone will. Read
`.claude/app-profile.md` first — it holds this project's names, ids, channel and commands, and this
skill is written against it, not against any one app.

**Applies to:** an Expo project (managed or prebuild) shipping through EAS Build and EAS Update. The
variant-split idea carries to bare React Native and to Android, but the specific mechanisms here —
`app.config.js`, config plugins, `eas.json` channels, `runtimeVersion` fingerprints — do not. Say so
rather than improvising an equivalent if the project turns out to be bare RN or Flutter.

**If there is no `.claude/app-profile.md` in this project**, that is the first thing to fix: copy
`app-profile.template.md` (beside the `two-app-setup` skill) to `.claude/app-profile.md` and fill it
in from the repo — `app.config.js`, `eas.json` and `package.json` carry almost every value. Do not
proceed on guessed ids or a guessed channel.

Two modes. Pick by whether the split already exists.

- **Audit** — a project that already has it. Run the checklist below; most of these faults report
  success while doing nothing.
- **Bootstrap** — a project that does not. Work down `## Bootstrap`.

State which mode you are in before you start, and never bootstrap over an existing config without
diffing it first.

**`TWO_APP_WORKFLOW.md`, beside this skill, is the long version** — why the pattern exists, how the
variant switch and the fingerprint work, and a numbered log of every way it broke on the project it
came from, each entry written as symptom → cause → rule. Read it when a check below fails and the
remedy is not obvious, or when someone asks why any of this is worth the setup cost. The audit list
here is that log compressed into commands.

---

## Why the pattern exists

The dev variant is the only one that talks to Metro, so it is the only one where a change is visible
in seconds. The distribution variant is the only one that is the real thing: it runs its embedded or
downloaded bundle, takes the production code path through `expo-updates`, and is signed and delivered
the way a tester receives it.

**Neither can stand in for the other, and the gap is not theoretical.** On 2026-08-31 the app's root
view background differed between them — `expo-updates` hands its deferred root view's colour to the
real React Native root view in a production build, and a dev client takes a different path and gets
RN's own white. The dev app looked correct while TestFlight showed a red frame around every
navigation transition. Anything that reads a native module the dev client happens to have, anything
that depends on how the bundle was delivered, and anything in the launch sequence before JS runs, can
only be judged on the distribution build.

Separate bundle ids are what let both sit on one phone. Before that split they overwrote each other
in place, so having the standalone build meant losing the dev build and vice versa.

---

## Audit

Run all of it. Each item names the symptom, because in every case the command that caused it
succeeded.

1. **The channel comes from `eas.json` build profiles and nowhere else.**
   ```bash
   grep -n "expo-channel-name\|requestHeaders" app.config.js
   python3 -c "import json;d=json.load(open('eas.json'));print({k:v.get('channel') for k,v in d['build'].items()})"
   ```
   A hardcoded `expo-channel-name` in `app.config.js`'s `updates.requestHeaders` is ignored by the
   build (EAS sets the real channel at build time) *and* misleading about where to publish.
   **Symptom when wrong: every `eas update` prints an update group id and no phone ever sees it.**
   Confirm the profile that built the installed app and the branch you publish to are the same word.

2. **`runtimeVersion.policy` is `fingerprint`.**
   ```bash
   grep -n -A3 "runtimeVersion" app.config.js
   ```
   Under `appVersion` with a pinned `version`, the runtime version is a constant, so adding a native
   module does not move it and an OTA will hand a bundle calling a missing native module to a build
   that has none. **Symptom when wrong: the app crashes on the screen that uses the new module.**
   Before switching, verify JS is not hashed — the count of sources under `src/` must be zero:
   ```bash
   npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; d=json.load(sys.stdin); s=d['sources']; print(len(s), sum(1 for x in s if str(x.get('filePath','')).startswith('src/')))"
   ```

3. **`fingerprint.config.js` covers what plugins copy but do not import.** The default scan hashes a
   config plugin's own JS, which is not the same as hashing what the plugin puts in the build. Every
   file a plugin or a config key reads by *path* — native sources, icon artwork, a splash sheet —
   needs an `extraSources` entry, or repainting it changes the binary while leaving the runtime
   version still. **Symptom when wrong: an OTA is delivered to a build with the old artwork or the
   old native module.**

4. **`eas.json` is hashed whole, `submit` section included.** Editing any part of it changes the
   runtime version and orphans every existing build from future updates — even a submit-only key that
   cannot affect the binary. **Rule: change `eas.json` immediately before a build, never after one.**
   To reach an already-submitted build after the fact, publish once from a tree with its own
   `eas.json` restored (`git show <build-commit>:eas.json > eas.json`), verify the fingerprint
   matches, then put it back.

5. **The dev client is excluded from the distribution build's autolinking.**
   ```bash
   ls plugins/ ; grep -rn "use_expo_modules" ios/Podfile 2>/dev/null
   ```
   `expo-dev-client` is a normal `package.json` dependency, so Expo's iOS autolinking links it into
   *every* variant regardless of the `plugins` array — that array only toggles the package's own
   config plugin. With `expo-dev-launcher` linked it becomes the app's entry point.
   **Symptom when wrong: the standalone build shows "no dev server found" instead of loading its
   bundle, while `EXUpdatesEnabled` is correctly true.** The fix is a `withDangerousMod` plugin
   patching the Podfile's `use_expo_modules!` call to
   `exclude: ['expo-dev-client', 'expo-dev-launcher']` for the non-dev variant — dev-launcher is only
   a transitive dependency and must be named separately.

6. **Export compliance is pre-answered**, if the app uploads to App Store Connect.
   ```bash
   grep -n "ITSAppUsesNonExemptEncryption" app.config.js
   ```
   Without it an upload sits at "Missing Compliance" until someone clicks through the encryption
   question by hand. **Symptom when wrong: a submit succeeds and the build never appears in
   TestFlight.** The flag is baked into the binary and **cannot apply retroactively** — builds made
   before it was added each need the answer once, by hand, forever.

7. **Publishing sources env from EAS, not the publisher's laptop.** `EXPO_PUBLIC_*` variables are
   inlined at bundle time, so an update published without `--environment production` carries whoever
   ran the command's own `.env` out to every tester. Mandatory from SDK 55; adopt it now regardless.

8. **The variant switch reaches the native project.** Only `expo prebuild` changes which variant
   `ios/` represents; setting the env var on `expo run:ios` does not.
   ```bash
   grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj
   ```
   That grep is how you find out rather than guessing.

Report each item as pass/fail with the evidence, not as a summary. A fail here is usually one line of
config and a rebuild.

---

## Bootstrap

Order matters — 1 and 2 change the native project, and everything after depends on which variant it
represents.

1. **Variant switch in `app.config.js`.** One boolean at the top, read by `name` and both platform
   ids:
   ```js
   const isDevelopmentVariant = process.env.APP_VARIANT === 'development'
   // name:             isDevelopmentVariant ? 'App Dev' : 'App'
   // ios.bundleIdentifier / android.package: '<id>.dev' : '<id>'
   ```
   Keep the suffix on the id, not a wholly different id — provisioning, keychain entries and any
   `grep` you write later all read better for it.

2. **Keep the dev client out of the distribution build.** Add `expo-dev-client` to `plugins` for the
   dev variant only, and a `withExcludeDevClient` plugin for every other variant (audit item 5). This
   is not optional and it is not obvious; skipping it produces a standalone build that looks broken
   in a way that points nowhere.

3. **Scripts that name the variant and the device.** In `package.json`:
   ```json
   "start":       "APP_VARIANT=development expo start",
   "ios":         "APP_VARIANT=development expo run:ios --device",
   "ios:preview": "expo run:ios --configuration Release --device"
   ```
   `--device` is deliberate here — see `.claude/app-profile.md`.

4. **`eas.json` profiles, one channel each.** A `development` profile with `developmentClient: true`
   and the variant env var; a `production` profile with `autoIncrement`, its channel, and
   `environment: production`. Write the `submit` section now, in the same edit — after the first build
   it is a fingerprint change (audit item 4).

5. **`runtimeVersion: { policy: 'fingerprint' }`** plus `fingerprint.config.js` for anything a plugin
   reads by path (audit items 2 and 3). Verify zero `src/` sources before relying on OTA for ordinary
   work.

6. **`updates.url` and no channel header.** The url is the EAS project's; the channel is `eas.json`'s
   job alone (audit item 1).

7. **Pre-answer export compliance** if the app will be submitted (audit item 6).

8. **Prebuild, verify, build both.**
   ```bash
   APP_VARIANT=development npx expo prebuild --platform ios --clean
   grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj   # must show the .dev id
   npm run ios
   ```
   The first build of a *new* bundle id usually needs one Xcode GUI run (▶ with the phone selected)
   to register the App ID and generate a first profile; terminal commands work for that id
   afterwards. On a free personal team, expect a 7-day signing clock on the local build and a cap of
   10 new App IDs per 7 days — that cap presents as a signing failure and is not a keychain problem.

9. **Write it down.** Add the equivalent of `.claude/app-profile.md` and a team guide, and copy the
   sibling skills (`ship-app`/`ship-dudu`, `ota-doctor`, `native-rebuild`) across. The traps in the
   audit list are the entire reason those files exist; a config without the note is a config that
   gets re-broken.

---

## Handing back

Never run `eas login`, an interactive submit, or anything wanting an Apple password on the user's
behalf — hand it over. Never commit the config changes unless asked.
