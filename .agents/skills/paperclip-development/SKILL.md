---
name: paperclip-development
description: Develop, run, test, and submit changes to the Paperclip macOS clipboard app. Use for work in this repository, including taking a PR through review and CI to a merge or a ready-for-merge handoff.
---

# Paperclip development

Read the repository's [AGENTS.md](../../../AGENTS.md) for product constraints and [README.md](../../../README.md) for build, manual acceptance, and release details. Keep clipboard data local and preserve its representations. Protect the Quick Search keyboard loop.

## Build, test, and run

The Xcode project is authoritative. On macOS with Xcode installed, run from the repository root:

```sh
xcodebuild \
  -project spaperclip.xcodeproj \
  -scheme spaperclip \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO \
  -only-testing:spaperclipTests \
  test
```

This builds and runs the unit suite without Apple signing credentials. For build-only, omit `-only-testing:spaperclipTests` and replace `test` with `build`.

Record whether production Paperclip is running. Before quitting it to run a development copy, notify the user that production clipboard capture will be paused. Quit it so monitors and global shortcuts do not compete, and use a separate history store:

```sh
SPAPERCLIP_UI_TEST_ID="dev-$(uuidgen)" \
  .build/DerivedData/Build/Products/Debug/Paperclip.app/Contents/MacOS/Paperclip
```

Paperclip launches quietly in the menu bar; open Clipboard History there or invoke Quick Search with the configured shortcut (default Control+Option+Space).

After testing, including failed or interrupted runs, quit the development copy. If you quit a running production copy, relaunch `/Applications/Paperclip.app` and verify it is running, unless the user asked otherwise. Always tell the user whether production was restarted. If restart fails or remains unverified, clearly report that production capture may still be paused and give the installed app path so the user can restart it. Never replace the installed app with an ad-hoc build; deployment uses the signed release process in README and requires a deployment request.

Use isolated named pasteboards for clipboard tests. Run focused checks while iterating and the relevant unit suite before submission. For window, focus, shortcut, or automatic-paste changes, perform the manual acceptance checks in README; XCUITest cannot reliably operate the accessory app's status menu or deliver its global hotkey. Documentation-only changes need skill/document validation, not an app rebuild.

## Submit and finish a PR

1. Start a `codex/` branch from current `origin/main`. Preserve unrelated local edits; use an isolated checkout when needed.
2. Commit and push the scoped change. Open a PR with a concise description of the resulting behavior and validation.
3. Poll CI, review summaries, and inline review threads. Wait for an actual completed review of the latest head commit; silence or a review of an older commit is insufficient. Codex's summary records the reviewed SHA and whether findings remain.
4. Address actionable findings, validate the changes, push, and obtain a fresh review. Request `@codex review` if a review is not automatically triggered. Repeat until the latest commit has no outstanding findings or unresolved review threads and all applicable CI checks pass. An intentional documentation-only CI skip is acceptable; report it explicitly.
5. If the user requested merging this PR, recheck its head SHA, review state, unresolved threads, and checks immediately before merging. Use `gh pr merge --merge --match-head-commit <reviewed-sha>` so a newer, unreviewed commit cannot slip in. Do not enable auto-merge before the review gate is satisfied.
6. Otherwise leave the PR open and present its link as **ready for merge**, with the review and check results. A request to submit a PR alone does not authorize merging, publishing a release, or deployment. If credentials, review quota, or an external failure blocks verification, report the blocker and leave the PR open rather than calling it ready.
