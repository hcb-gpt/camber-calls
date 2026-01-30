-- Restrict RPC to service_role only
REVOKE ALL ON FUNCTION public.upsert_idempotency_key(text, text, text, text, jsonb) FROM public;
REVOKE ALL ON FUNCTION public.upsert_idempotency_key(text, text, text, text, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.upsert_idempotency_key(text, text, text, text, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_idempotency_key(text, text, text, text, jsonb) TO service_role;;
