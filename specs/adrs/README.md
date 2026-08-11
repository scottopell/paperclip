# Architecture Decision Records

This shared chain records the point-in-time decisions that shape Paperclip's
requirements. Requirements define the standing user contract; these records
explain why significant tradeoffs were chosen.

## Quick reference

| ADR | Title | Status | Affects |
| --- | --- | --- | --- |
| [000](000_preserve-rich-local-history.md) | Preserve rich local history beside the text sync projection | Accepted | REQ-CH-002, REQ-CH-003, REQ-CH-008, REQ-CD-001, REQ-CD-009, REQ-CD-010 |
| [001](001_require-explicit-sync-opt-in.md) | Require explicit opt-in before clipboard sync | Accepted | REQ-CD-001, REQ-CD-007, REQ-CD-008, REQ-CD-010 |

## For agents: which decisions bind your task

| Task type | Relevant ADRs |
| --- | --- |
| Changing local clipboard persistence or representation fidelity | 000 |
| Adding or changing cross-device data fields | 000, 001 |
| Enabling network or CloudKit access for clipboard data | 001 |
| Changing sync defaults, consent, or account behavior | 001 |

## Decision dependencies

```text
ADR-000 (separate rich local history from the text sync projection)
   └── ADR-001 (require opt-in before that projection reaches CloudKit)
```

## Conventions

- Number ADRs sequentially across the project.
- Declare scope through `Affects:`, not directory placement.
- Freeze accepted ADRs. Supersede a decision with a new record rather than
  rewriting its history.
- Add every ADR to the quick-reference and agent-routing tables.
