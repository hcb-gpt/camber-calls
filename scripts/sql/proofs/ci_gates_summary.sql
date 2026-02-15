-- CI gate summary (PASS/FAIL + violation counts).
-- Run: scripts/query.sh --file scripts/sql/proofs/ci_gates_summary.sql

select *
from public.ci_gate_all()
order by gate_name;

