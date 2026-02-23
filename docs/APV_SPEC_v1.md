# APV Spec v1 (Tier-0)

## What this project is to spec
APV is the independent AI evidence verification authority instrument. Its sole function is to validate evidence packets
for integrity, reproducibility, and tamper resistance. It recomputes PacketId as SHA-256(manifest.json bytes) and verifies
sha256sums.txt against on-disk bytes. It emits deterministic verification_result.json and append-only receipts.

## Packet Constitution v1 Option A (assumed)
- manifest.json does NOT include packet_id
- packet_id.txt = SHA-256(manifest.json bytes)
- sha256sums.txt generated last and lists SHA-256 over files (excluding itself)

## Deterministic outputs
- verification_result.json is canonical JSON (UTF-8 no BOM, LF, stable key ordering)
- receipts append as canonical NDJSON

## Verdicts
APV produces deterministic verdict:
- VALID
- INVALID

with explicit reason_code.
