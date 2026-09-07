# App profile

Copy this to `.claude/app-profile.md` in the project and fill it in. The `two-app-setup`,
`ota-doctor` and `native-rebuild` skills read this file for every project-specific value, so they
hold none of their own — filling this in is what points them at a new app.

Delete rows that do not apply. Add rows rather than hardcoding a fact into a skill.

| | |
|---|---|
| Product name (distribution) | |
| Product name (dev variant) | |
| Bundle id / package (distribution) | |
| Bundle id / package (dev variant) | |
| Variant switch | `APP_VARIANT=development` (anything else ⇒ distribution) |
| Distribution route | TestFlight / Play internal testing / ad-hoc |
| Update channel | from `eas.json` build profiles — **never** `app.config.js` |
| Dead channels still holding updates | |
| EAS project id | |
| EAS account / owner | |
| CLI invocation | `npx eas-cli@latest …` — `npx eas` is a different, wrong package |
| App Store Connect app id | `eas.json` → `submit.production.ios.ascAppId` |
| Local signing team | |
| Paid membership held by | builds borrow EAS-stored credentials; submits need a live login |
| Platforms shipped | |
| iOS deployment target | |
| Xcode workspace | `ios/<Name>.xcworkspace` (name follows the variant last prebuilt) |
| Gates before shipping | e.g. `npm run typecheck && npm test` |
| Native-input files | `app.config.js`, `eas.json`, `plugins/`, artwork a plugin copies, packages with native modules |
| Extra fingerprint sources | `fingerprint.config.js` entries |

## Local commands

| | |
|---|---|
| Metro | |
| Build + install the dev variant | |
| Build the distribution variant locally | |
| Switch which variant `ios/` represents | `APP_VARIANT=<…> npx expo prebuild --platform ios --clean` |

## Standing constraints

Anything a skill must never do here, and anything that is expected rather than broken. Examples worth
stating if true:

- **Device vs simulator** — whether the simulator works for this app at all, and what the run scripts
  pass.
- **Never commit, push, or publish unless asked.** An OTA reaches every tester on the channel.
- **Free-team signing**, if any developer is on one: the 7-day install clock, the 10 App IDs per 7
  days cap, and any entitlement that has to be stripped.
