---
name: native-rebuild
description: Rebuild the dev variant after a native change, and switch which variant the local ios/ project represents. Use when a new native package was added, a config plugin or app.config.js changed, the dev app throws on launch or shows "app entry not found", or when the standalone build needs installing locally instead.
---

# Native rebuild

A native change does not reach either app through Metro. The dev client carries the same native layer
as the distribution build, so a new module has to be compiled into it too — otherwise the app throws
while the module graph is still evaluating, before it can name what failed.

Read `.claude/app-profile.md` for this project's variant names, ids and commands.

**Applies to:** an Expo project (managed or prebuild) shipping through EAS Build and EAS Update. The
variant-split idea carries to bare React Native and to Android, but the specific mechanisms here —
`app.config.js`, config plugins, `eas.json` channels, `runtimeVersion` fingerprints — do not. Say so
rather than improvising an equivalent if the project turns out to be bare RN or Flutter.

**If there is no `.claude/app-profile.md` in this project**, that is the first thing to fix: copy
`app-profile.template.md` (beside the `two-app-setup` skill) to `.claude/app-profile.md` and fill it
in from the repo — `app.config.js`, `eas.json` and `package.json` carry almost every value. Do not
proceed on guessed ids or a guessed channel.

## Is this actually a native change?

Native if it touches `app.config.js`, `eas.json`, `plugins/`, artwork a plugin copies by path, the
Expo SDK, or a package with an iOS module. Everything under `src/`, fonts, images and copy is JS and
needs no rebuild.

Do not judge by eye. The fingerprint is the answer:

```bash
npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; print(json.load(sys.stdin)['hash'])"
```

Compare against the hash before your change (`git stash` it, or read the last build's hash from
`eas-cli build:list`). Unmoved ⇒ nothing to rebuild.

## Diagnose before rebuilding

**"app entry not found", with no module name and no stack, is the signature of a native module
missing from the binary.** An Expo package usually resolves its native module at *import* time, so
an import that throws leaves the app never registering its root component. `expo-system-ui`
announced itself exactly this way on 2026-08-31. Two things worth knowing before you spend a build
on it:

- A `try` around the `require` does **not** contain it. Metro's own module loader catches a factory
  error, reports it to `ErrorUtils` and returns `undefined` rather than rethrowing, so LogBox still
  shows a full-screen uncaught error.
- For a call that is merely cosmetic, `requireOptionalNativeModule('<ModuleName>')` from
  `expo-modules-core` (in every binary, returns `null`) lets you check *before* requiring the package
  at all, and keeps the dev client alive on an older binary.

A **black, frozen** dev client is a different fault: it cannot reach Metro. Campus and guest wifi
routinely isolate the phone from the Mac. Test with an iPhone hotspot before touching the build.

Also confirm what the current `ios/` folder actually is, rather than assuming:

```bash
grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj
```

## Rebuild the dev variant

```bash
rm -rf ios/Pods ios/build ios/Podfile.lock
APP_VARIANT=development npx expo prebuild --platform ios --clean
grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj   # must show the .dev id
npm run ios
```

**Only `expo prebuild` switches the variant.** Setting `APP_VARIANT` on `expo run:ios` does not, and
the grep is how you find out rather than guessing. Getting this wrong installs one variant's native
project under the other's name, which surfaces later as the standalone build showing a dev-server
screen, or a dev build that cannot find Metro.

If a fix seems to be ignored by the rebuild, clear Xcode's cache too:

```bash
rm -rf ios/Pods ios/build ios/Podfile.lock ~/Library/Developer/Xcode/DerivedData
npx expo run:ios --device
```

If `expo run:ios`'s device launch is flaky, build with `xcodebuild` and install with
`xcrun devicectl` — the simulator is not an option for this app.

## Switching back to the distribution variant locally

```bash
APP_VARIANT= npx expo prebuild --platform ios --clean
grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj   # must show the plain id
npm run ios:preview
```

Skipping the prebuild is the direct cause of the standalone app showing "no dev server found" after a
reinstall — the native project it installed was still the dev one.

## First build of a bundle id

The first time *this machine* builds a given bundle id, Apple's automatic signing usually needs one
Xcode GUI run: open the workspace, select the phone, hit ▶ once. Terminal commands work for that id
afterwards. On a free personal team, two clocks apply and neither is a misconfiguration — the install
expires roughly every 7 days, and only 10 new App IDs can be registered per 7 days. That cap presents
as a signing failure; do not go looking in the keychain for it.

## After the rebuild

A native change also means the distribution build is now behind, and no OTA can close the gap — the
client will decline a bundle whose fingerprint does not match. Say so, and hand the build decision to
the user rather than starting one.
