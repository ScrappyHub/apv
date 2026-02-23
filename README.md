# APV — AI Provenance Validator (Tier-0)

APV is a deterministic, offline, standalone verification instrument. It validates AI evidence packets for:
- Packet Constitution v1 Option A integrity
- PacketId recomputation correctness (SHA-256 of manifest.json bytes)
- sha256sums.txt correctness against on-disk payload bytes
- structural completeness and tamper detection

APV does NOT record or generate AI outputs. HAAI is the recorder. APV is the validator.

## Tier-0 Selftest
Run:
- scripts\_selftest_apv_v1.ps1

Selftest builds a minimal valid packet and multiple tamper cases, then asserts deterministic VALID/INVALID outcomes.
