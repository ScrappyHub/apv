# APV Upload Prefix Contract v1 (Folder-Prefix Ingest)

## Bucket
Default bucket: `apv-evidence` (override worker env `APV_BUCKET`).

## Object Key Prefix (deterministic)
For each run, the UI uploads evidence under:

`u/<uid>/p/<project_id>/r/<run_id>/`

Example:
`u/05ef.../p/9d2c.../r/2b14.../evidence.json`

## Run row fields
`apv.runs.evidence_prefix` MUST be set to exactly the prefix above, including trailing slash.

Worker behavior:
- Lists objects under the prefix
- Downloads all objects
- Writes to: `C:\ProgramData\APV\work\<run_id>\...`
- Emits receipts: `C:\ProgramData\APV\receipts\apv_worker.ndjson`

Verifier wiring comes next:
- After ingest, the worker will invoke the deterministic APV verifier nucleus and publish verdict + receipts.
