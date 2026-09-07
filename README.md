# claude-kit

Claude Code skills that are worth having in **every** project, kept in version control instead of
loose in `~/.claude/`.

Right now that is one coherent set: shipping a React Native / Expo app to a phone, where two builds
of the same codebase live side by side — a Metro-connected dev variant and a standalone distribution
build.

## Install

```bash
git clone <this repo> ~/Documents/claude-kit
cd ~/Documents/claude-kit && ./install.sh
```

`install.sh` symlinks each `skills/<name>/` into `~/.claude/skills/` and `CLAUDE.md` into
`~/.claude/CLAUDE.md`. Because they are links, editing a skill here takes effect immediately — no
reinstall step to forget. It refuses to overwrite anything it did not create, so an existing
`~/.claude/CLAUDE.md` is reported and skipped rather than lost. `--copy` if symlinks are awkward on a
machine, `--dry-run` to see what it would do.

Skills are read at session start, so **restart Claude Code** after installing.

## What is in here

| | |
|---|---|
| `skills/ship-app` | Get a change onto the phone. Decides native vs JS by comparing fingerprints, then takes the OTA route or the build + submit route. |
| `skills/two-app-setup` | Stand up the dev/distribution variant split in a project that lacks it, or audit an existing config against the failures that report success. Carries the long-form writeup and the profile template. |
| `skills/ota-doctor` | Triage an update that will not appear on the phone: cold-launch count, fingerprint vs installed build, channel, publish environment, build expiry. |
| `skills/native-rebuild` | Rebuild the dev client after a native change, switch which variant local `ios/` represents, and diagnose the launch failure that names no module. |
| `CLAUDE.md` | Loaded into every project session. A pointer to the above, nothing more — it must stay short, since it costs context in projects that will never use it. |
| `skills/two-app-setup/TWO_APP_WORKFLOW.md` | Why the two-app split is worth the setup cost, how the variant switch and the runtime-version fingerprint work, and a log of every way it broke with the rule each failure left behind. |

## The one rule that makes them portable

**No skill here contains an app-specific value.** No bundle ids, no channel names, no team ids, no
account names. Each reads `.claude/app-profile.md` in whatever project it is invoked from, and a
project without one gets it from `skills/two-app-setup/app-profile.template.md` before anything else
happens.

That is the whole porting story for a new app: fill in one page. If a skill ever needs a fact the
template does not cover, add a row to the template — never a constant to the skill.

## Adding a skill

The bar these were written to: **the chore recurs, *and* the wrong version of it looks like the right
one.** Shipping qualifies because publishing to a dead channel prints a success id. Running the tests
does not — it fails loudly, and a line in a project's `CLAUDE.md` is enough.

What the existing ones do, worth matching:

1. Name the decision before the commands. Picking the wrong route is usually the actual failure.
2. Replace judgement with a measurement. Where a skill would say "check whether", give the command
   whose output is the answer.
3. Write each trap as **symptom → cause → rule**. Whoever reads it is already looking at the symptom.
4. Put project values in the profile, mechanism in the skill.
5. Record what was deleted and why, or a dead route looks like an oversight and gets re-added.
6. Hand interactive and irreversible steps back — no logins, no commits, no publishing unasked.
7. Write `description` as the user's own trigger phrases. It is the only thing matched against a
   request.

## Provenance

Extracted from the Dudu iOS project (`~/Documents/Dudu/dudu_iOS`) on 2026-09-07, where the pattern
and every setback in `TWO_APP_WORKFLOW.md` actually happened. That repo keeps the canonical copy of
the writeup and its own `.claude/app-profile.md`; this keeps the mechanism.
