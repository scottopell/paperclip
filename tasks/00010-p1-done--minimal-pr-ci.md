# Add minimal pull-request CI

## Goal

Catch compile and unit-test regressions with the smallest useful GitHub Actions footprint.

## Delivered

- One macOS 15 job runs the Debug production build and unit suite in a single `xcodebuild test` invocation.
- CI runs on pull requests targeting `main`, never on pushes to `main`.
- Documentation-only and task-only changes do not consume macOS runner time.
- Superseded runs cancel automatically per pull request.
- A 10-minute timeout prevents stuck jobs from consuming unbounded minutes.
- Manual dispatch remains available for an explicit recheck.

## Intentionally excluded

- XCUITests
- Release builds
- OS/Xcode matrices
- Dependency caching
- Post-merge `main` runs
