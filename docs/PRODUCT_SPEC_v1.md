# APV Product Surface v1 (Monorepo)

## What APV is (product layer)
APV is a model-agnostic evidence verification application.

- Inputs: Packet Constitution v1 / HashCanon v1 Option-A directory packets
- Outputs: deterministic verification_result.json + append-only receipts
- Guarantees: verifier is the authority; UI/API never invents truth

APV UI/API is a Tier-1 surface on top of the Tier-0 verifier nucleus.

## Tier boundaries
- Tier-0 nucleus (already shipped in repo root):
  - scripts/apv_verify_v1.ps1
  - scripts/_selftest_apv_v1.ps1
  - scripts/_RUN_apv_tier0_evidence_v1.ps1

- Tier-1 product surface (this scaffold):
  - apps/web  : Next.js UI (Supabase auth + storage + DB)
  - apps/api  : Node API/worker that runs the verifier and writes results back
  - supabase/ : migrations for app tables + RLS

## Model-agnostic contract
APV never couples to PIE or any one model provider.
Any model/tool is supported if it can produce a PCv1 Option-A packet.

## Minimal data model
- projects: owned by auth user
- runs: owned by auth user; references project

## Execution model (target)
1) UI uploads packet evidence to Supabase Storage
2) UI creates run row (status=queued)
3) Worker claims queued run
4) Worker downloads packet dir, runs verifier, uploads outputs
5) UI shows verdict + receipts

## Next steps
- Implement folder-prefix packet ingestion (download prefix -> local dir -> verify)
- Add run timeline + receipt viewer UI
- Add Figma Make pass later for visual polish
