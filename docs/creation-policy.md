# Task creation policy boundary

The Python planner emits one source/occurrence/target intent per opted-in birthday.
The adapter uses the canonical Soma Core Python validator for session capability
and each receipt. The functions remain injectable for host conformance tests.
There is no duplicate validator, JavaScript engine, installed CLI or native auth
requirement in the task writer.

`pyproject.toml` and `uv.lock` pin the public `soma` library to commit
`5f23a6efa39c5f010c688a5f6b9f0359b2547c23`. Its standard-library-only
`soma.creation.validate_creation_session` and
`validate_creation_receipt` functions match contract
`40ce1fb59bfe27a26bc878b193d694414c3b491fdc365cb421a96000b6b1c3a0`.
Core independently verifies cross-language parity and actual Worker receipts.

Tests use the public policy `birthdays-tasks-v1`, revision
`8231fa18788c8a475e08a1e788623c1d94872961636afff2e0924396a7fbd68c`.
That service policy allows only `title`, `due_date`, and `person_ids`; namespace,
source kind, integer occurrence and origin are fixed service-side. Test coverage
is not evidence of deployed configuration, a credential, historical dedupe
coverage, or authorization to activate the writer. Optional planner fields are
omitted unless explicitly chosen and supported by a separately configured policy.
No live policy or credential is compiled into the caller.

The HTTP tests verify requests and failure behavior against the real pinned
Python checks, including direct injection and tuple-to-list scope normalization.
They do not claim to test the service's SQL atomicity. Core owns that transaction
and its Worker integration tests. Existing and tombstoned targets stay untouched;
adopted missing never falls back; the caller preserves earlier receipts when later
requests fail and does not infer creation from `existing`.
