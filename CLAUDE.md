# Personal notes

## Mobile projects (Expo / React Native)

There is a portable kit for running **two builds of one app side by side on a phone** — a
Metro-connected dev variant beside a standalone distribution build — installed at user scope, so it
is available in every project:

- `~/.claude/skills/two-app-setup/TWO_APP_WORKFLOW.md` — why the split is worth it, how the variant
  switch, the update channel and the `runtimeVersion` fingerprint work, a log of every way it broke
  with the rule each failure left behind, and a checklist for porting it to a new app.
- Skills: **`/ship-app`** (get a change onto the phone, OTA or a new build), **`/two-app-setup`**
  (bootstrap or audit the split), **`/ota-doctor`** (an update that will not appear on the phone),
  **`/native-rebuild`** (rebuild the dev client, switch which variant local `ios/` represents).

All four read `.claude/app-profile.md` in the current project for its names, ids, channel and
commands, and hold none of their own. A project without that file gets one from
`~/.claude/skills/two-app-setup/app-profile.template.md` before anything else happens.

The kit assumes Expo + EAS. The idea carries to bare React Native, the mechanisms do not — say so
rather than improvising an equivalent.
