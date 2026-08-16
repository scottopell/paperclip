# ADR-001: Require Explicit Opt-In Before Clipboard Sync

- **Status:** Accepted
- **Date:** 2026-08-10 (formalized from project design law)
- **Affects:** REQ-CD-001, REQ-CD-007, REQ-CD-008, REQ-CD-010

## Context

Clipboard history routinely contains passwords, tokens, private messages, and
other user data copied for a momentary local task. CloudKit offers convenient
cross-device delivery through the user's iCloud account, but enabling it changes
the product from local-only storage to networked storage. Merely installing the
iOS companion or being signed into iCloud is not a clear expression of consent
for transmitting clipboard history.

## Options considered

1. **Keep clipboard history local-only.** This provides the strongest privacy
   default and the smallest system, but offers no cross-device workflow.
2. **Synchronize automatically whenever iCloud is available.** This minimizes
   setup and makes the companion appear seamless, but uploads private clipboard
   data without a deliberate user choice.
3. **Keep sync off by default and require explicit opt-in.** This adds a setup
   state and user-facing explanation, but preserves informed control while still
   supporting cross-device access.

## Decision

Adopt option 3. Clipboard sync is disabled until the user explicitly enables it
after being told that text history will be stored in their private iCloud data.
Disabling sync stops new transmissions without compromising the local clipboard
history path. The application must not imply that a pending change reached
another device until the sync boundary can support that claim.

## Consequences

- **Positive:** Network access remains a conscious product choice and the local
  default matches the sensitivity of clipboard data.
- **Negative:** Delivery requires consent UI, persisted preference state, and
  clear behavior for records already present in CloudKit when sync is disabled.
- **Neutral:** iCloud account availability is necessary but not sufficient to
  enable clipboard sync.

## References

- [`../cross-device-sync/requirements.md`](../cross-device-sync/requirements.md)
- [`../../AGENTS.md`](../../AGENTS.md), Product law 2
- [ADR-000](000_preserve-rich-local-history.md)
