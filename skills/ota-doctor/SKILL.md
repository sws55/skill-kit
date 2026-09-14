---
name: ota-doctor
description: Triage an over-the-air update that will not appear on the phone. Use when a change is on the distribution build's channel but the app still shows the old behaviour, when someone asks "why isn't my change showing up", or before publishing, to confirm an update can land at all.
---

# OTA doctor

Every failure mode here reports success. `eas update` prints an update group id whether or not any
phone can ever read it, and a client that declines a mismatched update says nothing at all — it just
keeps running the bundle it already has. So do not reason about which one it is; run the checks in
order and stop at the first fail.

Read `.claude/app-profile.md` for the channel, the project id and the CLI invocation.

**Applies to:** an Expo project (managed or prebuild) shipping through EAS Build and EAS Update. The
variant-split idea carries to bare React Native and to Android, but the specific mechanisms here —
`app.config.js`, config plugins, `eas.json` channels, `runtimeVersion` fingerprints — do not. Say so
rather than improvising an equivalent if the project turns out to be bare RN or Flutter.

**If there is no `.claude/app-profile.md` in this project**, that is the first thing to fix: copy
`app-profile.template.md` (beside the `two-app-setup` skill) to `.claude/app-profile.md` and fill it
in from the repo — `app.config.js`, `eas.json` and `package.json` carry almost every value. Do not
proceed on guessed ids or a guessed channel.

## 0. Rule out the normal case first

**An update lands on the second cold launch, not the first.** A launch downloads it in the background
and the launch after that runs it. Ask how many times the app has been fully closed and reopened —
force-quit, not backgrounded — since publishing. If the answer is one, that is the whole explanation
and everything below is wasted work.

## 1. Does the fingerprint match the installed build?

```bash
npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; print(json.load(sys.stdin)['hash'])"
npx eas-cli@latest build:list --limit 5 --platform ios --json --non-interactive | python3 -c "import json,sys; [print(b['id'][:8], b['buildProfile'], b['updateChannel']['name'], b['fingerprint']['hash'][:8], b['status']) for b in json.load(sys.stdin)]"
```

`runtimeVersion` is `fingerprint`, so this is not advice — it is what the client enforces. Different
hashes mean the update was never offered.

**If they differ, find out what moved**, because the answer changes the remedy:

```bash
git log --oneline -15 -- app.config.js eas.json plugins/ fingerprint.config.js package.json
```

- A **real native change** (a new module, a permission, a plugin, icon or splash artwork) ⇒ the build
  has to come first. There is no way round it and that is the policy working.
- **`eas.json` edited after the build** ⇒ the runtime version moved for nothing. `eas.json` is hashed
  whole, `submit` section included, so even a submit-only key orphans every existing build. To rescue
  an already-submitted build:
  ```bash
  git show <build-commit>:eas.json > eas.json
  npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; print(json.load(sys.stdin)['hash'])"   # must now match the build
  # publish, then restore eas.json
  ```
  Then say plainly that the next build closes it properly.
- **`package-lock.json` changed since the last install** ⇒ the local hash describes a
  `node_modules` no build has. The fingerprint hashes what is installed, not the lockfile;
  `npm ci`, regenerate, and compare again before reading anything else into the diff. (Seen
  2026-09-14: a teammate's lockfile pin of `react-native-worklets` 0.8.3 → 0.5.1, never installed
  locally, moved the hash for ten days and failed an EAS build at `CONFIGURE_EXPO_UPDATES`.)
- **Nothing obvious moved** ⇒ compare the source lists rather than guessing:
  ```bash
  npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; [print(s.get('type'), s.get('filePath') or s.get('id')) for s in json.load(sys.stdin)['sources']]" | sort
  ```
  A local, gitignored `ios/` contributes a null hash, so local and CI agree; a stray file that a
  plugin reads by path will show up here.

## 2. Did it go to the channel the app reads?

```bash
npx eas-cli@latest update:list --branch <channel> --limit 5 --non-interactive
```

The installed build's channel is in the `build:list` output above. Publishing to a branch no build
listens on is the single most expensive mistake available here, because it looks exactly like
success. Check the branch spelling against the profile, not against memory or an older note.

## 3. Was the update published from the right tree, with the right env?

```bash
npx eas-cli@latest update:list --branch <channel> --limit 1 --json --non-interactive
```

Look at the commit and whether the tree was dirty. Then confirm `--environment production` was used:
`EXPO_PUBLIC_*` variables are inlined at bundle time, so an update published without it carries the
publisher's own `.env` — which can *look* like a broken update when a key is stale or missing, and is
also how a laptop's keys reach every tester. If in doubt, republish with the flag.

## 4. Is the app actually on that build?

A TestFlight build expires after 90 days and a tester on an expired one is running whatever they last
had. The EAS artifact expires after 30 days, which is how long a finished build can still be
submitted. Neither is recoverable by publishing; both need a build.

## Report

Say which check failed and what the remedy is, in one or two sentences. If everything passes, say so
and name the update group id and the build it targets — the honest answer is then "it landed, the app
needs a second cold launch", not a hunt for another cause.

Do not publish anything to fix this without being asked. An OTA reaches every tester on the channel.
