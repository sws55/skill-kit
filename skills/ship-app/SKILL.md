---
name: ship-app
description: Get a change onto the phone — an over-the-air EAS Update to the distribution build, or a new build when the change is native. Use when the user says "ship it", "eas update", "OTA", "push to TestFlight", "new build", "update the app on my phone", or asks why a change is not showing up on the real build.
---

# Ship app

Two ways a change reaches the phone, and picking the wrong one is the whole reason this skill exists.
**Decide native vs JS first**, then follow that path.

Read **`.claude/app-profile.md`** for this project's names, ids, channel, gates and commands. This
skill holds none of them. If that file does not exist, create it from
`~/.claude/skills/two-app-setup/app-profile.template.md` before shipping anything — publishing to a
guessed channel is the most expensive mistake available here, and it looks like success.

**Applies to** an Expo project shipping through EAS Build and EAS Update. If the project turns out to
be bare React Native or Flutter, say so rather than improvising an equivalent.

## Is the change native?

Native if it touches `app.config.js`, `eas.json`, `plugins/`, artwork a plugin copies by path, a new
or upgraded package with a native module, or the SDK. Everything under `src/`, fonts, images and copy
is JS. The profile's *native-input files* row is authoritative for this project.

You do not have to judge this by eye, and you should not. Compare the fingerprint against the last
build — **after `npm ci`**, because the fingerprint hashes the `node_modules` that is installed, not
the lockfile, and EAS recomputes it from a clean install and fails the build on any disagreement
(`CONFIGURE_EXPO_UPDATES`, "Runtime version mismatch"). A `git pull` that touched
`package-lock.json` leaves a stale install describing a native layer no build can reproduce:

```bash
npm ci
npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; print(json.load(sys.stdin)['hash'])"
npx eas-cli@latest build:list --limit 1 --platform ios --json --non-interactive | python3 -c "import json,sys; b=json.load(sys.stdin)[0]; print(b['buildProfile'], b['updateChannel']['name'], b['fingerprint']['hash'])"
```

Same hash, an OTA will land. Different hash, it will not — the build has to come first. With
`runtimeVersion.policy: 'fingerprint'` this is not advice, it is what the client enforces: a
mismatched update is never offered, and the app silently keeps running its embedded bundle.

If the hashes differ and no native change was intended, hand it to `/ota-doctor` rather than
guessing — an `eas.json` edit made *after* the last build is the usual cause and has its own remedy.

## Path A — JS-only, over the air

```bash
<the profile's gate commands, e.g. npm run typecheck && npm test -- --runInBand>
git status
APP_VARIANT= npx eas-cli@latest update --branch <channel> --environment production --message "<what changed>"
```

- **`APP_VARIANT=` empty**, so the bundled config is the distribution app's name and id, not the dev
  variant's.
- **`--branch` is the channel the installed build listens on**, from the profile — not whatever an
  older note or a dead channel says. Publishing to a branch no build reads prints an update group id
  and reaches nobody.
- **`--environment production` is not optional.** `EXPO_PUBLIC_*` variables are inlined into the
  bundle at publish time, so without it the update carries the API keys from *whoever ran the
  command's* local `.env` out to every tester. The flag sources them from EAS instead, and is
  mandatory from SDK 55.
- Commit first if the change should be in the update — EAS records the commit, and a dirty tree is
  flagged on the published update. Committing is the user's call; ask.
- Report the update group id, and say that the app takes it on its **next cold launch**, having
  downloaded it on the launch before. The first reopen after publishing usually still shows the old
  build. That is normal, not a fault.

## Path B — native, via a new build

```bash
npx eas-cli@latest build --profile production --platform ios
npx eas-cli@latest submit --profile production --platform ios
```

- 15–25 min for the build, then the store's processing before it appears to testers.
- `autoIncrement` handles the build number, and with `appVersionSource: remote` the version must not
  be hand-edited to force anything.
- If `submit` in `eas.json` has no app id recorded, the submit asks interactively. **Hand that back
  to the user** rather than answering it — and note that adding the id afterwards is itself a
  fingerprint change (see the traps).
- **Building and submitting need different credentials.** Building borrows the signing credentials
  stored on the EAS project, so anyone with access can run it. Submitting needs a live store login
  with a paid team behind it; `You have no team associated with your Apple account` is that account
  being accurate, not a misconfiguration. The profile names who holds it.
- A build ships its JS embedded and sets its own fingerprint, so there is no need to publish an
  update straight after one.

## After a native change, the dev client is behind too

It carries the same native layer, so a new native module has to be compiled into it or the app throws
on the import — usually as `app entry not found`, with no module name. Use **`/native-rebuild`**;
do not duplicate its recipe here.

## Traps that each cost a build cycle

- **`eas.json` is a fingerprint source, hashed whole.** Editing any part of it — including `submit`,
  which cannot affect the binary — changes the runtime version and orphans every existing build from
  OTA updates. Change it immediately *before* a build, never after. To reach an already-shipped build
  afterwards, publish once from a tree with the old file restored
  (`git show <build-commit>:eas.json > eas.json`), verify the fingerprint matches, then put it back.
- **An iOS upload sits at "Missing Compliance"** until the export-encryption question is answered, so
  a submit can succeed and the build never appear. `ITSAppUsesNonExemptEncryption` in `app.config.js`
  pre-answers it, is baked into the binary, and **cannot apply retroactively** — builds made before
  it was added each need the answer by hand, once.
- **Fingerprint sources a plugin reads but does not import** need a `fingerprint.config.js` entry, or
  repainting an asset changes the binary while the runtime version stays still.
- **A stale `node_modules` fails the build at `CONFIGURE_EXPO_UPDATES`** with "Runtime version
  mismatch" and a JSON diff naming the package. The fix is `npm ci`, not a config change — and the
  dev client built on the stale install is then behind too (Reanimated/worklets check JS against
  native at startup), so it needs `/native-rebuild`.
- **EAS build logs are brotli-encoded.** `build:view <id> --json` lists a `logFiles` URL served as
  `Content-Encoding: br`; system `curl` saves raw bytes. `brotli -d`, then filter the JSON lines on
  `phase` to find the one that failed.

## Guardrails

- An OTA reaches **every tester on that channel**. Confirm what is in it before publishing.
- Never `git commit`, push, or publish because the work seems finished. All three are the user's call.
- Never run `eas login` or anything interactive non-interactively — hand it over.
- If an update genuinely will not appear on the phone, do not iterate on it here: `/ota-doctor` checks
  the cold-launch count, the fingerprint, the channel and the publish environment in that order.
