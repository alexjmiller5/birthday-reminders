# Task creation policy boundary

The Python planner emits one source/occurrence/target intent per opted-in birthday.
The adapter requires an injected canonical Life Core validator for the session
capability and each receipt. It has no default implementation and no live caller.
Core's pure-Python boundary will be a separately reviewed, pinned dependency.
There is no JavaScript runtime in the Modal image.

Synthetic tests execute the reviewed public `life-core/creation` exports using
Bun 1.4.2. The test fixture is a minimal browser-target ESM bundle, with no replica
runtime, package resolution, source maps or machine paths. Its source is Life
Data commit `57c71d3f12542936a0db497a3eb6da8ddf11a94b`, contract
`40ce1fb59bfe27a26bc878b193d694414c3b491fdc365cb421a96000b6b1c3a0`.
Fixture SHA-256: `56bd9923bfa82fa30d5e4318b9a16a66862856ed49e66ec565791a5bc63aa6f9`.

Reproduce from a checkout of that exact source:

```sh
bun build <life-core-checkout>/core/src/creation.ts --target=browser --format=esm --minify --outfile=tests/fixtures/life-creation.js
```

Tests use the prospective public policy `birthdays-tasks-v1`, revision
`8231fa18788c8a475e08a1e788623c1d94872961636afff2e0924396a7fbd68c`.
That service policy allows only `title`, `due_date`, and `person_ids`; namespace,
source kind, integer occurrence and origin are fixed service-side. Test coverage
is not evidence of deployed configuration, a credential, historical dedupe
coverage, or authorization to activate the writer. Optional planner fields are
omitted unless explicitly chosen and supported by a separately configured policy.

The HTTP tests verify the consumer's requests and failure behavior against the
canonical checks. They do not claim to test the service's SQL atomicity. Core owns
that transaction and its Worker integration tests. Existing and tombstoned targets
stay untouched; adopted missing never falls back; the caller preserves earlier
receipts when later requests fail and does not infer creation from `existing`.
