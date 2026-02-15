import { applyBizDevCommitmentGate, classifyBizDevProspect } from "./bizdev_guardrails.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected=${String(expected)} actual=${String(actual)}`);
  }
}

Deno.test("bizdev classifier: detects prospect intake signals with high confidence", () => {
  const classification = classifyBizDevProspect(
    "we are in the initial stages and looking to remodel. schedule a meeting and text me your name and address",
  );

  assertEquals(
    classification.call_type,
    "bizdev_prospect_intake",
    "call type should be bizdev prospect intake",
  );
  assertEquals(classification.confidence, "high", "confidence should be high");
  assert(
    classification.evidence_tags.some((tag) => tag.includes("initial stage")),
    "should include initial stage evidence",
  );
  assert(
    classification.evidence_tags.some((tag) => tag.includes("looking to")),
    "should include looking-to evidence",
  );
  assert(
    classification.evidence_tags.some((tag) => tag.includes("schedule")),
    "should include meeting evidence",
  );
});

Deno.test("bizdev commitment gate: strips project_id when no commitment-to-start evidence", () => {
  const gated = applyBizDevCommitmentGate({
    transcript:
      "we are looking to get a quote and are in the initial stages, schedule a meeting and text me your address",
    decision: "assign",
    project_id: "proj-123",
  });

  assertEquals(gated.classification.call_type, "bizdev_prospect_intake", "classification should be bizdev");
  assertEquals(gated.classification.commitment_to_start, false, "commitment evidence should be absent");
  assertEquals(gated.decision, "review", "assign should be downgraded to review");
  assertEquals(gated.project_id, null, "project_id must be removed when commitment is missing");
  assertEquals(gated.reason, "bizdev_without_commitment", "reason code should reflect the gate");
});

Deno.test("bizdev commitment gate: allows project assignment once commitment evidence exists", () => {
  const gated = applyBizDevCommitmentGate({
    transcript:
      "we are looking to start next month. contract is signed, deposit paid, and we have a start date on the calendar",
    decision: "assign",
    project_id: "proj-123",
  });

  assertEquals(gated.classification.call_type, "bizdev_prospect_intake", "classification should still be bizdev");
  assertEquals(gated.classification.commitment_to_start, true, "commitment evidence should be present");
  assertEquals(gated.decision, "assign", "assign should remain assign when commitment exists");
  assertEquals(gated.project_id, "proj-123", "project_id should be preserved with commitment evidence");
  assertEquals(gated.downgraded, false, "gate should not downgrade with commitment evidence");
});

Deno.test("GT cll_06DJF923KDWYQ6P10C8WEZ6MCR: spans 0+1 classify BizDev/Prospect Intake (HIGH)", () => {
  const span0Transcript =
    "my wife and i have a house in watkinsville we're looking to either do a larger addition and we're kind of in the initial stages";
  const span1Transcript =
    "you just tell me what you got available and we'll schedule you in. could you do me a favor then just text me your name and address";

  const span0 = classifyBizDevProspect(span0Transcript);
  const span1 = classifyBizDevProspect(span1Transcript);

  assertEquals(span0.call_type, "bizdev_prospect_intake", "span 0 should be bizdev");
  assertEquals(span0.confidence, "high", "span 0 should classify high");
  assertEquals(span1.call_type, "bizdev_prospect_intake", "span 1 should be bizdev");
  assertEquals(span1.confidence, "high", "span 1 should classify high");
});
