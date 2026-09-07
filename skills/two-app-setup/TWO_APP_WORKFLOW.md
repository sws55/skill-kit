> **Portable copy.** Canonical source is `docs/TWO_APP_WORKFLOW.md` in the Dudu repo
> (`~/Documents/Dudu/dudu_iOS`), which is version-controlled and where edits should go; this copy
> lives beside the `two-app-setup` skill so the pattern is readable from any project. The setback log
> is a record of events that already happened, so the two do not drift in practice — but if you
> change one, copy it across.

# The two-app workflow — Dudu and Dudu Dev

How this project keeps two builds of one codebase on the same phone, why that is worth the setup
cost, and every way it broke on the way there. Written to be portable: the final section is a
checklist for standing the same thing up in another Expo / React Native app, and the Claude Code
skills that automate it are designed to be copied across (`docs/SKILLS.md`).

Companion documents: `docs/TEAM_SETUP.md` is the step-by-step for a new machine; CLAUDE.md's
**Shipping** section is the short version a session reads automatically.

---

## 1. What the two apps are

| | Dudu Dev | Dudu |
|---|---|---|
| bundle id | `com.dudusg.app.dev` | `com.dudusg.app` |
| built by | locally, `npm run ios` | `eas build --profile production` |
| JS comes from | Metro, over wifi | the `production` update channel, or the bundle it shipped with |
| signed by | your own Apple ID | the paid team's credentials, stored on EAS |
| arrives via | a cable and Xcode | TestFlight |
| what it is for | second-by-second iteration | what a tester actually sees |

They are the same blueprint and physically different binaries. Both stay installed. The mental model
that survived contact: a **workbench** copy wired up to diagnostic equipment, and a **showroom** copy
that works on its own.

---

## 2. Why two, and not one

### Iteration speed is only available from Metro

A dev client reloads a JS change in about a second. Nothing else in the pipeline is close: an OTA
update is a minute plus two cold launches, and a build is twenty minutes plus Apple's processing.
Doing ordinary UI work against anything but Metro is not a slower workflow, it is a different job.

### But a dev client cannot tell you what a tester sees

This is the half that is easy to under-rate until it costs a day. The dev client differs from the
real app in ways that have nothing to do with your code:

- **`expo-updates` paints a deferred root view in a production build and hands its colour to the real
  React Native root view.** A dev-client build takes a different path and gets RN's own white. The
  practical result on 2026-08-31: the splash colour showed through the rounded corners of every
  native-stack transition, framing each Settings back-swipe in red — on TestFlight only. The dev app
  looked right the whole time.
- **The dev client has native modules the distribution build may not**, and vice versa. Whichever was
  built last is what you are testing against.
- **`expo-dev-launcher`, when linked, is the app's entry point.** Its presence changes what "launch"
  even means.
- Delivery itself is under test in the real app: whether the bundle downloaded, whether the runtime
  version matched, whether the channel was right. A dev client answers none of those questions
  because it never asks them.

So the two apps are not redundancy. Each is the only instrument for something the other cannot
measure, and a change is not done until it has been seen on both.

### Separate bundle ids, so neither displaces the other

Before the split (`ef0b950`), a dev build and a standalone build overwrote each other in place — the
same id, the same slot on the home screen. Having one meant losing the other, so "check it on the
real build" cost a full reinstall in each direction and simply did not happen. A `.dev` suffix on the
id is the entire mechanism, and it is what makes the discipline above affordable.

### One switch drives all of it

`APP_VARIANT=development` is read once at the top of `app.config.js`, and the name, the iOS bundle
id, the Android package and the plugin list all derive from that boolean. There is no second source
of truth, no parallel config file, and nothing to keep in sync by hand.

---

## 3. How it works

### The variant switch

```js
// app.config.js
const isDevelopmentVariant = process.env.APP_VARIANT === 'development'

name: isDevelopmentVariant ? 'Dudu Dev' : 'Dudu',
ios: { bundleIdentifier: isDevelopmentVariant ? 'com.dudusg.app.dev' : 'com.dudusg.app' },
plugins: [
  ...(isDevelopmentVariant ? ['expo-dev-client'] : ['./plugins/withExcludeDevClient']),
  …
]
```

`package.json`'s scripts set the variable so nobody has to remember it:

```json
"start":       "APP_VARIANT=development expo start",
"ios":         "APP_VARIANT=development expo run:ios --device",
"ios:preview": "expo run:ios --configuration Release --device"
```

**Only `expo prebuild` switches which variant the local `ios/` folder represents.** Setting the
variable on `expo run:ios` does not, which is why every recipe in this project ends with
`grep -m1 PRODUCT_BUNDLE_IDENTIFIER ios/*.xcodeproj/project.pbxproj` — you find out rather than
guessing.

### Keeping the dev client out of the standalone build

`expo-dev-client` is an ordinary `package.json` dependency, because `npm run ios` needs it every day.
Expo's iOS autolinking therefore links it into **every** variant regardless of the `plugins` array —
that array toggles the package's own config plugin (Info.plist edits and such), not native module
autolinking. With `expo-dev-launcher` linked, it becomes the app's root entry point, and the
standalone build shows "no dev server found" instead of loading its bundle, while `EXUpdatesEnabled`
sits correctly at `true` in `Expo.plist` the whole time.

`plugins/withExcludeDevClient.js` patches the generated Podfile's `use_expo_modules!` call to
`exclude: ['expo-dev-client', 'expo-dev-launcher']` for the non-development variant.
`expo-dev-launcher` has to be named separately: it is only a transitive dependency, never listed in
`package.json`, and autolinking picks it up from `node_modules` on its own.

### Channels, and where they come from

`eas.json`'s build profiles carry the channel, and nothing else does. `production` → the `production`
branch → TestFlight. The `preview` profile and channel still exist, still hold updates, and no phone
listens to them. `app.config.js` deliberately declares no `expo-channel-name` at all.

### Runtime version, and why an OTA is ever refused

```js
runtimeVersion: { policy: 'fingerprint' }
```

The runtime version is a hash of the native layer — the plugin list, native dependencies, the config
keys that reach Info.plist, and `eas.json`. A client only accepts an update whose runtime version
matches its own, so a JS bundle can never be delivered to a binary that lacks the native module it
calls. JS is not hashed (verified: 79 sources, zero under `src/`), so ordinary work still ships over
the air.

`fingerprint.config.js` adds what the default scan misses: the default hashes a config plugin's own
JS, which is not the same as hashing what the plugin **puts in the build**. `withAlternateIcons`
copies `plugins/native/*` and `assets/icons/*` into Xcode, and `ios.splash.image` copies
`assets/splash.png` into the storyboard. The evaluated config carries the *path*, not the bytes, so
repainting an asset in place would change the binary while leaving the runtime version still.

### The two routes onto a phone

| change | route | time |
|---|---|---|
| anything under `src/`, fonts, images, copy | `eas update --branch production --environment production` | ~1 min + two cold launches |
| `app.config.js`, `eas.json`, `plugins/`, plugin-copied artwork, a native package, the SDK | `eas build --profile production` then `submit` | 15–25 min + Apple processing |

Use `/ship-dudu`; it decides which by comparing fingerprints rather than by eye.

---

## 4. Setbacks, and the rule each one left behind

Roughly chronological. The pattern worth noticing: **almost every one of these failed by reporting
success.** That is the argument for writing them down rather than trusting anyone to spot them again.

**1 · The two apps overwrote each other.** One bundle id, one home-screen slot. Fixed by deriving the
id from `APP_VARIANT` (`ef0b950`). *Rule: separate ids first, before any of the rest is worth doing.*

**2 · The standalone build showed the dev-launcher's "no dev server found" screen.** The `plugins`
array had `expo-dev-client` removed for that variant, which does nothing to autolinking (§3). Fixed
by `withExcludeDevClient` (`5e60fd7`). *Rule: a package's presence in `plugins` is not what links it;
`package.json` is.*

**3 · The simulator crashes this app** (RNGestureHandler), so every run script carries `--device` and
all verification is on hardware. When `expo run:ios`'s launch is flaky, `xcodebuild` plus
`xcrun devicectl` is the way in. *Rule: decide early whether the simulator is viable, because every
later instruction inherits the answer.*

**4 · `APP_VARIANT` on `expo run:ios` does not switch the variant.** Only `expo prebuild` does. This
produced installs of one variant's native project under the other's name, surfacing much later as a
launch failure that pointed nowhere. *Rule: verify with the `grep`, never assume.*

**5 · Every OTA this project ever published went to a channel no phone reads.** `app.config.js`
hardcoded `expo-channel-name: preview` in `updates.requestHeaders` while the TestFlight build was
made on the `production` profile. EAS sets the real channel at build time, so the hardcode was both
ignored by the build *and* misleading about where to publish — and `eas update --branch preview`
printed a fresh update group id every single time (`5bb186d`). *Rule: the channel lives in `eas.json`
and nowhere else. A successful-looking publish is not evidence of anything.*

**6 · The runtime version was the constant `1.0.0`.** Under `runtimeVersion.policy: 'appVersion'`
with `version` pinned, adding `expo-image-picker` did not move it, so an update would have handed a
bundle calling `ExponentImagePicker` to a build with no such module — a crash on opening the bug
report screen. Switched to `fingerprint` (`5bb186d`). *Rule: a runtime version that never changes is
a promise nobody is keeping.*

**7 · The fingerprint missed what plugins copy.** Hashing `withAlternateIcons.js` says nothing about
the ObjC module and the icon artwork it copies into Xcode. `fingerprint.config.js` and its
`extraSources` exist for exactly that gap, and `assets/splash.png` was added to it later for the same
reason. *Rule: add an entry for any file a plugin or a config key reads but does not import.*

**8 · Adding `ascAppId` to `eas.json` orphaned an already-submitted build from every future OTA.**
`eas.json` is hashed **whole**, `submit` section included — a setting that cannot affect the binary
still moved the runtime version. Proven by substitution: restoring build 4's own `eas.json`
reproduced its fingerprint exactly, which is the only reason that day's update reached it at all
(`20d2a5e`). *Rule: change `eas.json` immediately before a build, never after one. The rescue is to
publish once from a tree with the old file restored, fingerprint verified, then put it back.*

**9 · A build uploaded cleanly and never appeared in TestFlight.** App Store Connect holds every
upload at "Missing Compliance" until the export-encryption question is answered by hand.
`ITSAppUsesNonExemptEncryption: false` answers it at build time, and `false` is the correct answer
rather than a shortcut — the app makes ordinary HTTPS calls and implements no crypto of its own. It
is **per-binary and cannot apply retroactively**: builds 3, 4 and 5 predate the flag and each needed
the answer once, forever (`20d2a5e`). *Rule: when a submit succeeds and nothing arrives, look at App
Store Connect before assuming the submit failed.*

**10 · An update published without `--environment production` carries the publisher's own `.env`.**
`EXPO_PUBLIC_*` variables are inlined at bundle time, so the keys on whoever ran the command's laptop
go out to every tester on the channel. On 2026-08-31 that accidentally *helped* — the publisher's keys
were valid and patched a build that had none — which is precisely why it is worth writing down; stale
or dev keys would have shipped the same way with nothing flagging it (`5ab6bf2`). *Rule: the flag is
not optional, and becomes mandatory at SDK 55 anyway.*

**11 · Building and submitting need different credentials.** Building borrows the signing credentials
stored on the EAS project, so anyone with project access can run it. Submitting needs a live Apple
login with a paid team behind it, and anyone else gets `You have no team associated with your Apple
account` — Apple being accurate, not a misconfiguration. Recorded in `eas.json`'s `submit` section so
the last interactive prompt in the pipeline stops being asked (`49af342`, and see setback 8 for what
that edit cost). *Rule: an App Store Connect API key is the fix worth doing; without one, submitting
has a single named human in it.*

**12 · A native change takes the dev client down without naming itself.** An Expo package usually
resolves its native module at *import* time, so an import that throws while the module graph is still
evaluating means the app never registers its root component — and the dev client reports **"app entry
not found"**, with no module name and no stack. `expo-system-ui` did this on 2026-08-31. A `try`
around the `require` does not contain it either: Metro's loader catches a factory error, reports it
to `ErrorUtils` and returns `undefined` instead of rethrowing. *Rule: rebuild the dev client after
every native change, and for a merely cosmetic call, gate it on
`requireOptionalNativeModule('<ModuleName>')` — which is in every binary and returns `null`.*

**13 · The dev app looked right while TestFlight did not** (the root-view colour, §2). *Rule: verify
anything touching launch, native theming or the update path on the distribution build. The dev client
is not a witness.*

**14 · A black, frozen dev client is a network fault, not a build fault.** Campus and guest wifi
isolate the phone from the Mac, so the dev client cannot reach Metro. An iPhone hotspot is the
fastest test. *Rule: check reachability before spending a rebuild on it.*

**15 · Free-team friction, all of it expected.** A locally-signed dev install expires roughly every 7
days; only 10 new App IDs can be registered per 7 days, and that cap presents as a signing failure
rather than as a quota message; `aps-environment` has to be stripped
(`plugins/withStripApsEnvironment.js`) because every notification in this app is local. A paid
membership removes the first two. *Rule: none of these are worth debugging as if they were
misconfiguration.*

**16 · Two expiry clocks, and they are not the same one.** A TestFlight build stops launching after
**90 days**, and no OTA rescues it — an update needs a host build to attach to. The EAS artifact
expires after **30 days**, which is how long a finished build can still be submitted. *Rule: expect a
build roughly quarterly whether or not anything native changed.*

**17 · The first reopen after publishing still shows the old build.** A launch downloads the update
in the background; the launch after that runs it. *Rule: cold-launch twice before believing something
is broken — it is the first thing `/ota-doctor` checks, and often the whole answer.*

---

## 5. What this costs, honestly

Two builds means two things to keep current. A native change is not done when the TestFlight build
ships — the dev client carries the same native layer and throws on the import until it is rebuilt too
(setback 12). The fingerprint policy converts "I think this is JS-only" into a hard gate, which is
correct, and which also means a one-line `app.config.js` edit now costs a full build cycle.

The cost is real and it is smaller than the alternative. Every setback in §4 that survived more than
an hour did so because a command reported success. The split, the fingerprint, and the two documented
routes are what make those failures *visible* rather than cheap to cause.

---

## 6. Porting this to another React Native app

Use the `/two-app-setup` skill — it does this and audits an existing config against §4. If you are
doing it by hand, the order matters, because steps 1–2 change the native project and everything after
depends on which variant it represents.

1. **Derive the app name and both platform ids from one env var** in `app.config.js`
   (`APP_VARIANT === 'development'`). Keep the dev id as a `.dev` suffix of the real one.
2. **Exclude the dev client from every non-dev variant** with a `withDangerousMod` plugin patching
   the Podfile's `use_expo_modules!` to `exclude: ['expo-dev-client', 'expo-dev-launcher']`. Copy
   `plugins/withExcludeDevClient.js` verbatim; it is self-contained. Skipping this produces setback 2,
   which points nowhere.
3. **Write the scripts** so nobody sets the variable by hand, and decide the simulator question now
   (`--device` or not).
4. **`eas.json`: one channel per profile**, and write the `submit` section in the *same* edit —
   afterwards it is a fingerprint change (setback 8).
5. **`runtimeVersion: { policy: 'fingerprint' }`**, plus a `fingerprint.config.js` listing every file
   a plugin or config key reads by path. Confirm JS is not hashed before relying on OTA:
   ```bash
   npx expo-updates fingerprint:generate --platform ios | python3 -c "import json,sys; d=json.load(sys.stdin); s=d['sources']; print(len(s), sum(1 for x in s if str(x.get('filePath','')).startswith('src/')))"
   ```
6. **`updates.url` only — no `expo-channel-name`** anywhere in `app.config.js` (setback 5).
7. **Pre-answer export compliance** if the app will be submitted (setback 9).
8. **Prebuild, verify the bundle id with the `grep`, build both variants.** Expect one Xcode GUI run
   per new bundle id on this machine.
9. **Copy the skills and the profile**: `.claude/skills/` and `.claude/app-profile.md`, then rewrite
   the profile for the new app. That is the whole port — the skills read the profile and hold no
   Dudu-specific values of their own. `ship-dudu` is the one exception; rename it and swap its table
   for the new app's, or write the generic `ship-app` equivalent from it.
10. **Write down the traps that bit you**, in the file that actually gets read. Here that is CLAUDE.md's
    Shipping section, this document, and the skills — deliberately three places, because the failures
    are silent and the skill is what gets run.
