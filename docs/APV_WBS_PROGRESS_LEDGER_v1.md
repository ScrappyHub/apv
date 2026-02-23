# APV — WBS Progress Ledger v1

## Phase 0 — Spec lock (COMPLETE)
- Identity + boundaries locked
- Tier-0 DoD defined

## Phase 1 — Core verifier (IN PROGRESS)
- Implement PacketId recomputation
- Implement sha256sums verification
- Emit deterministic verification_result.json
- Emit append-only receipts

## Phase 2 — Golden vectors (IN PROGRESS)
- Positive vector (VALID)
- Negative vectors (tamper cases)

## Phase 3 — CLI packaging (PENDING)
- Stable entrypoint script
- Deterministic exit codes and output files

## Phase 4 — Seal + golden run (PENDING)
- Selftest GREEN on clean machine
- Receipt bundle captured and pinned
