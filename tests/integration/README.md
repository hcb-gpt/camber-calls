# Call Pipeline Integration Scaffold

This scaffold validates the five-function call chain:

`process-call -> segment-call -> segment-llm -> context-assembly -> ai-router`

It uses canonical fixture `cll_06DSX0CVZHZK72VCVW54EH9G3C` as transcript/input
source and includes negative-path coverage for:

- missing transcript
- null phone
- malformed interaction_id

## Run

```bash
RUN_PIPELINE_INTEGRATION=1 \
SUPABASE_URL=... \
SUPABASE_SERVICE_ROLE_KEY=... \
EDGE_SHARED_SECRET=... \
deno test --allow-env --allow-net tests/integration/call_pipeline_scaffold_test.ts
```

When `RUN_PIPELINE_INTEGRATION` is not set to `1`, tests are skipped.
