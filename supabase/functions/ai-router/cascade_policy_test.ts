import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.218.0/assert/mod.ts";

type Decision = "assign" | "review" | "none";

interface ProviderResult {
  ok: boolean;
  provider: "openai" | "anthropic";
  model: string;
  project_id: string | null;
  confidence: number;
  decision: Decision;
  reasoning: string;
  anchors: unknown[];
  strong_anchor: boolean;
  error_code?: string;
}

interface StagePair {
  openai: ProviderResult | null;
  anthropic: ProviderResult | null;
}

function isStrongAssign(result: ProviderResult | null): boolean {
  return !!result &&
    result.ok &&
    result.decision === "assign" &&
    !!result.project_id &&
    result.confidence >= 0.75 &&
    result.anchors.length > 0 &&
    result.strong_anchor;
}

function chooseHigherConfidence(
  a: ProviderResult | null,
  b: ProviderResult | null,
): ProviderResult | null {
  if (!a) return b;
  if (!b) return a;
  if (a.confidence === b.confidence) return a;
  return a.confidence >= b.confidence ? a : b;
}

function simulateCascade(stages: StagePair[]) {
  const warnings: string[] = [];
  const reasonCodes = new Set<string>();
  let fallbackWinner: { result: ProviderResult; stage: number } | null = null;
  let sawProviderError = false;

  for (let i = 0; i < stages.length; i++) {
    const stage = i + 1;
    const openai = stages[i].openai;
    const anthropic = stages[i].anthropic;
    const stageResults = [openai, anthropic].filter((r): r is ProviderResult =>
      !!r
    );

    for (const result of stageResults) {
      if (!result.ok || result.error_code) {
        sawProviderError = true;
      }
    }

    const openaiAssign = isStrongAssign(openai);
    const anthropicAssign = isStrongAssign(anthropic);

    if (openaiAssign && anthropicAssign) {
      if (openai!.project_id === anthropic!.project_id) {
        const winner = chooseHigherConfidence(openai!, anthropic!)!;
        warnings.push(`stage_${stage}_consensus_assign`);
        return {
          winner,
          winnerStage: stage,
          consensusAssign: true,
          warnings,
          reasonCodes: Array.from(reasonCodes),
          sawProviderError,
        };
      }
      reasonCodes.add("model_disagreement");
      warnings.push(`stage_${stage}_model_disagreement`);
    } else if (openaiAssign || anthropicAssign) {
      reasonCodes.add("model_disagreement");
      warnings.push(`stage_${stage}_single_provider_assign`);
    } else if (stageResults.length > 0 && stageResults.every((r) => !r.ok)) {
      warnings.push(`stage_${stage}_all_provider_failed`);
    }

    const validResults = stageResults.filter((r) => r.ok);
    if (validResults.length > 0) {
      const best = validResults.sort((a, b) => b.confidence - a.confidence)[0];
      fallbackWinner = { result: best, stage };
    }
  }

  if (fallbackWinner && fallbackWinner.result.decision === "assign") {
    fallbackWinner = {
      stage: fallbackWinner.stage,
      result: {
        ...fallbackWinner.result,
        project_id: null,
        decision: "review",
        reasoning:
          `${fallbackWinner.result.reasoning} [downgraded: model_disagreement_after_final_stage]`,
      },
    };
    reasonCodes.add("model_disagreement");
  }

  if (sawProviderError) reasonCodes.add("model_error");
  if (warnings.length === 0) warnings.push("model_disagreement");

  return {
    winner: fallbackWinner?.result || null,
    winnerStage: fallbackWinner?.stage || null,
    consensusAssign: false,
    warnings,
    reasonCodes: Array.from(reasonCodes),
    sawProviderError,
  };
}

Deno.test("cascade: consensus assign requires same project from both providers", () => {
  const outcome = simulateCascade([
    {
      openai: {
        ok: true,
        provider: "openai",
        model: "o1",
        project_id: "p1",
        confidence: 0.82,
        decision: "assign",
        reasoning: "openai assign",
        anchors: [{}],
        strong_anchor: true,
      },
      anthropic: {
        ok: true,
        provider: "anthropic",
        model: "a1",
        project_id: "p1",
        confidence: 0.91,
        decision: "assign",
        reasoning: "anthropic assign",
        anchors: [{}],
        strong_anchor: true,
      },
    },
  ]);

  assertEquals(outcome.consensusAssign, true);
  assertEquals(outcome.winnerStage, 1);
  assertEquals(outcome.winner?.project_id, "p1");
  assertEquals(outcome.winner?.decision, "assign");
  assert(outcome.warnings.includes("stage_1_consensus_assign"));
});

Deno.test("cascade: disagreement downgrades fallback assign to review", () => {
  const outcome = simulateCascade([
    {
      openai: {
        ok: true,
        provider: "openai",
        model: "o1",
        project_id: "p1",
        confidence: 0.88,
        decision: "assign",
        reasoning: "openai picks p1",
        anchors: [{}],
        strong_anchor: true,
      },
      anthropic: {
        ok: true,
        provider: "anthropic",
        model: "a1",
        project_id: "p2",
        confidence: 0.86,
        decision: "assign",
        reasoning: "anthropic picks p2",
        anchors: [{}],
        strong_anchor: true,
      },
    },
  ]);

  assertEquals(outcome.consensusAssign, false);
  assertEquals(outcome.winner?.decision, "review");
  assertEquals(outcome.winner?.project_id, null);
  assert(outcome.reasonCodes.includes("model_disagreement"));
  assert(outcome.warnings.includes("stage_1_model_disagreement"));
});

Deno.test("cascade: provider errors propagate model_error reason code", () => {
  const outcome = simulateCascade([
    {
      openai: {
        ok: false,
        provider: "openai",
        model: "o1",
        project_id: null,
        confidence: 0,
        decision: "review",
        reasoning: "timeout",
        anchors: [],
        strong_anchor: false,
        error_code: "provider_timeout",
      },
      anthropic: {
        ok: true,
        provider: "anthropic",
        model: "a1",
        project_id: null,
        confidence: 0.62,
        decision: "review",
        reasoning: "needs review",
        anchors: [],
        strong_anchor: false,
      },
    },
  ]);

  assertEquals(outcome.consensusAssign, false);
  assert(outcome.reasonCodes.includes("model_error"));
  assertEquals(outcome.sawProviderError, true);
});
