# Repository instructions

These instructions apply to the entire repository. They are mandatory for
human- or agent-assisted changes.

## Project objective

Modernize gmusicbrowser for GTK4, Wayland, current Linux audio, GNOME/Ubuntu,
and KDE Plasma without redesigning the application. Existing behaviour, data,
layouts, workflows, information density, and project character are compatibility
requirements.

Before substantial work, read:

- `MODERNIZATION.md`
- `docs/modernization/PROGRESS.md`
- `docs/modernization/ROADMAP.md`
- `docs/modernization/TECHNICAL_PLAN.md`
- `docs/modernization/INVENTORY.md`
- `docs/modernization/DECISIONS.md`
- `docs/modernization/REMOTE_FILES.md` when touching files, scanning, metadata,
  playback resources, or remote sources

Accepted decisions and milestone gates constrain implementation. Do not bypass
them for a quicker demonstration.

## Preservation rules

- Preserve GTK3 operation until the GTK4 parity gate explicitly retires it.
- Port behaviour before changing presentation or implementation style.
- Treat `.layout` syntax, widget identifiers, commands, saved configuration,
  and unknown options as compatibility APIs.
- Do not remove, rename, simplify, or silently approximate an established
  workflow without a documented and accepted decision.
- Do not combine the GTK port with a language rewrite or unrelated cleanup.
- Do not replace proven library, filter, queue, tag, layout, or random-mode
  logic merely because a new implementation looks cleaner.
- Keep stock GNOME, Ubuntu's GNOME session, and KDE Plasma as the initial tested
  desktop targets. Do not add a required GNOME Shell extension.

## Native coding style

New code must look as though it belongs beside the surrounding code. Study the
file and nearby functions before editing it.

- Match local indentation, tabs, alignment, brace placement, whitespace,
  naming, package organization, callback structure, and control-flow style.
- In established Perl files, retain the prevailing `sub Name` followed by the
  opening brace on the next line and the local compact expression style.
- Follow existing `use strict`, `use warnings`, package-variable, constant, and
  initialization conventions in the file being changed.
- Use the existing localization form for every user-visible string.
- Prefer established project helpers and idioms over introducing a second way
  to perform the same operation.
- Make narrow, reviewable changes. Do not reformat surrounding code or run a
  bulk formatter.
- Do not modernize unrelated Perl syntax while replacing toolkit APIs.
- Do not introduce a framework, class system, dependency-injection layer, or
  deep wrapper hierarchy without a demonstrated project requirement.
- Preserve existing copyright and licence headers. For new files, use a header
  consistent with nearby files without falsely attributing new work to an
  existing author.
- Do not add generated-code or AI attribution to source, comments, diagnostics,
  documentation, or commit messages.

Comments must match the existing terse, practical style:

- Explain a compatibility constraint, invariant, workaround, non-obvious API
  behaviour, or reason for a decision.
- Do not narrate obvious statements or restate the code in prose.
- Avoid tutorial text, generic docblocks, decorative section banners, emojis,
  speculative TODO lists, and commentary about the development process.
- Do not rewrite untouched historical comments merely to change their wording.
- Do not delete an old workaround until tests or primary API documentation show
  that it is obsolete.

Style compatibility is part of review. Functionally correct code that visibly
clashes with its file is not complete.

## Architecture constraints

- Shared core modules must not import Gtk3, Gtk4, GDK, or Wnck.
- A GTK4 entry point must not load Gtk3. Keep frontend-specific code behind the
  GTK3 or GTK4 boundary described in the technical plan.
- Commands and state changes must not require a widget when they belong in the
  shared application model.
- Keep playback, storage, desktop services, and layout parsing behind their
  documented contracts.
- Do not perform a mechanical repository-wide `Gtk3` to `Gtk4` replacement.
- Do not use removed X11 concepts to make a Wayland feature appear functional.
- Preserve unknown configuration and plugin values across round trips.
- Assign explicit, non-overlapping file ownership during parallel work. Freeze
  or communicate shared interface changes before downstream agents implement
  against them. One integrator reviews and tests the combined result.

## Library and filesystem safety

Offline, missing, and deleted are distinct states.

- Startup, playback errors, unavailable storage, permission failures, empty
  mountpoints, and partial or cancelled scans must never delete song records.
- Only a complete, source-identity-verified scan may commit a presence
  generation. It may soft-mark a song missing; it may not hard-delete it.
- Quarantine an empty result or unexpected mass disappearance instead of
  treating it as intentional deletion.
- Permanent purge is a separate explicit user action with source and count
  review.
- Preserve ratings, labels, play history, artwork associations, queue entries,
  and saved-list membership while media is unavailable.
- Never test a migration against the user's only configuration or library copy.
- Never store credentials in source identities, song URIs, playlists, logs, or
  crash reports.

## Editing discipline

- Inspect the worktree first. Existing changes belong to the user unless proven
  otherwise; do not overwrite or reformat them.
- Use `rg`/`rg --files` for repository searches and `apply_patch` for manual
  edits.
- Do not use destructive git commands. Do not commit, amend, rebase, or push
  unless the user explicitly requests it.
- Do not silently install packages, download test data, or add network-dependent
  tests.
- Keep temporary data outside the repository or in ignored task-specific paths.
  Use temporary XDG directories for UI tests and never point tests at the real
  user profile.
- Avoid broad cleanup in a compatibility patch. Record separately discovered
  work unless it is required for the current change.

## Verification requirements

Every changed porting unit must be tested in proportion to its risk.

- Syntax-check every changed Perl file.
- Run focused automated tests and relevant existing tests.
- Keep new tests deterministic and offline by default.
- For GTK4 UI work, test with `GDK_BACKEND=wayland` on a real Wayland connection;
  an X11 or XWayland fallback is not a Wayland pass.
- Use timeouts for GUI smoke tests and isolated D-Bus/XDG state where practical.
- Test the GTK3 path after changes to shared code.
- Compare GTK3 and GTK4 with the same fixture, configuration, layout, and action
  sequence when claiming parity.
- Exercise keyboard, pointer, focus, menus, drag-and-drop, accessibility, and
  saved-setting behaviour where relevant; rendering alone is insufficient.
- Run `git diff --check` and inspect the final diff for unrelated churn, debug
  output, unnecessary comments, and style drift.
- Never claim a test passed if it was skipped, fell back to another backend, or
  was only reasoned about.

If a required dependency or environment is unavailable, report the exact check,
failure, and smallest action needed. Do not replace evidence with an untested
stub.

## Completion standard

A feature is complete only when its implementation, compatibility behaviour,
failure handling, tests, and relevant documentation agree. Report what actually
works, commands executed, results, files changed, GTK3 regression status, and
remaining limitations.
