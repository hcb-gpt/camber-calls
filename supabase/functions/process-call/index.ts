/**
 * process-call Edge Function v3.9.0
 * Full v3.6 pipeline in Supabase - Ported from v4.0.22 context_assembly
 *
 * @version 3.9.0
 * @date 2026-01-30
 * @port context_assembly v4.0.22 - 6-source ranking, word boundaries, speaker stripping
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GATE = { PASS: "PASS", SKIP: "SKIP", NEEDS_REVIEW: "NEEDS_REVIEW" };
const ID_PATTERN = /^cll_[a-zA-Z0-9_]+$/;

// ============================================================
// V3 PORTED UTILITIES (from context_assembly v4.0.22)
// ============================================================

/** Strip speaker labels from transcript to avoid false alias matches
 * e.g., "Zachary Sittler:" should NOT match "Sittler" project */
function stripSpeakerLabels(text: string): string {
  return (text || "").replace(
    /(^|\n)\s*[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s*:/g,
    "$1",
  );
}

/** Word-boundary-aware term search - prevents partial word matches */
function findTermInText(textLower: string, termLower: string): number {
  const idx = textLower.indexOf(termLower);
  if (idx < 0) return -1;
  const before = idx === 0 ? " " : textLower[idx - 1];
  const afterIdx = idx + termLower.length;
  const after = afterIdx >= textLower.length ? " " : textLower[afterIdx];
  const isWordChar = (ch: string) => /[a-z0-9]/i.test(ch);
  if (isWordChar(before) || isWordChar(after)) return -1;
  return idx;
}

/** Normalize alias terms (dedupe, min length) */
function normalizeAliasTerms(terms: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const t0 of terms) {
    const t = (t0 || "").trim();
    if (!t) continue;
    const low = t.toLowerCase();
    if (seen.has(low)) continue;
    if (low.length < 4) continue;
    seen.add(low);
    out.push(t);
  }
  return out;
}

// ============================================================
// CANDIDATE TYPES
// ============================================================
type CandidateProject = {
  project_id: string;
  project_name: string;
  assigned: boolean;
  affinity_weight: number;
  sources: string[];
  alias_matches: { term: string; match_type: string }[];
  rank_score: number;
};

// ============================================================
// ORIGINAL HELPERS
// ============================================================
function m1(raw: any) {
  const a = { ...raw };
  if (a.transcript_text && !a.transcript) a.transcript = a.transcript_text;
  if (!a.interaction_id && a.call_id) a.interaction_id = a.call_id;
  return a;
}

function m4(n: any) {
  const r: string[] = [];
  if (n.interaction_id && !ID_PATTERN.test(n.interaction_id)) {
    r.push("G1_ID_MALFORMED");
  }
  if ((n.transcript || "").length < 10) r.push("G4_EMPTY_TRANSCRIPT");
  if (!n.event_at_utc && !n.call_start_utc) r.push("G4_TIMESTAMP_MISSING");
  return { decision: r.length > 0 ? GATE.NEEDS_REVIEW : GATE.PASS, reasons: r };
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  const run_id = `run_${t0}_${Math.random().toString(36).slice(2, 8)}`;

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  let raw: any;
  try {
    raw = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const iid = raw.interaction_id || raw.call_id || `unknown_${run_id}`;
  const id_gen = !raw.interaction_id && !raw.call_id;

  let audit_id: number | null = null, cr_uuid: string | null = null;
  let contact_id: string | null = null, contact_name: string | null = null;
  let project_id: string | null = null, project_name: string | null = null;
  let project_source: string | null = null;
  let project_confidence: number | null = null;

  // V3 ported: candidate tracking
  const candidatesById = new Map<string, {
    project_id: string;
    assigned: boolean;
    affinity_weight: number;
    sources: string[];
    alias_matches: { term: string; match_type: string }[];
  }>();
  const sources_used: string[] = [];

  try {
    // IDEMPOTENCY
    if (!id_gen) {
      const { error } = await db.from("idempotency_keys").insert({
        key: iid,
        interaction_id: iid,
        source: raw.source || "edge",
        router_version: "v3.9.0",
      });
      if (
        error &&
        (error.message?.includes("duplicate") ||
          error.message?.includes("23505"))
      ) {
        await db.from("event_audit").insert({
          interaction_id: iid,
          gate_status: "SKIP",
          gate_reasons: ["G1_DUPLICATE_EXACT"],
          source_system: "edge_v3.9",
          source_run_id: run_id,
          pipeline_version: "v3.9",
        });
        return new Response(
          JSON.stringify({
            ok: true,
            run_id,
            decision: "SKIP",
            reason: "duplicate",
            interaction_id: iid,
            ms: Date.now() - t0,
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    // AUDIT STARTED
    const { data: ad } = await db.from("event_audit").insert({
      interaction_id: iid,
      gate_status: "STARTED",
      gate_reasons: [],
      source_system: "edge_v3.9",
      source_run_id: run_id,
      pipeline_version: "v3.9",
      processed_by: "process-call",
      persisted_to_calls_raw: false,
      i1_phone_present: !!(raw.from_phone || raw.to_phone),
      i2_unique_id: !id_gen,
    }).select("id").single();
    if (ad) audit_id = ad.id;

    // M1: Normalize input
    const n = m1(raw);
    const phone = n.to_phone || n.other_party_phone || n.contact_phone;

    // ========================================
    // CONTACT RESOLUTION
    // ========================================
    if (phone) {
      const { data } = await db.rpc("lookup_contact_by_phone", {
        p_phone: phone,
      });
      if (data?.[0]) {
        contact_id = data[0].contact_id;
        contact_name = data[0].contact_name;
        sources_used.push("lookup_contact_by_phone");
      }
    }

    // ========================================
    // V3 PORTED: 6-SOURCE CANDIDATE COLLECTION
    // ========================================

    // Helper to add/update candidate
    const addCandidate = (pid: string, source: string, weight = 0) => {
      if (!pid) return;
      const cur = candidatesById.get(pid) || {
        project_id: pid,
        assigned: false,
        affinity_weight: 0,
        sources: [],
        alias_matches: [],
      };
      if (!cur.sources.includes(source)) cur.sources.push(source);
      if (weight > 0) {
        cur.affinity_weight = Math.max(cur.affinity_weight, weight);
      }
      candidatesById.set(pid, cur);
    };

    // SOURCE 1: project_contacts (direct assignment)
    if (contact_id) {
      const { data: pcRows } = await db
        .from("project_contacts")
        .select("project_id")
        .eq("contact_id", contact_id);

      if (pcRows?.length) {
        sources_used.push("project_contacts");
        for (const r of pcRows) {
          if (r.project_id) {
            const cur = candidatesById.get(r.project_id) || {
              project_id: r.project_id,
              assigned: true,
              affinity_weight: 0,
              sources: ["project_contacts"],
              alias_matches: [],
            };
            cur.assigned = true;
            if (!cur.sources.includes("project_contacts")) {
              cur.sources.push("project_contacts");
            }
            candidatesById.set(r.project_id, cur);
          }
        }
      }
    }

    // SOURCE 2: correspondent_project_affinity (historical call frequency)
    if (contact_id) {
      const { data: affRows } = await db
        .from("correspondent_project_affinity")
        .select("project_id, weight")
        .eq("contact_id", contact_id);

      if (affRows?.length) {
        sources_used.push("correspondent_project_affinity");
        for (const r of affRows) {
          if (r.project_id) {
            addCandidate(
              r.project_id,
              "correspondent_project_affinity",
              r.weight || 0,
            );
          }
        }
      }
    }

    // SOURCE 3: existing_project from interactions (replay fallback)
    {
      const { data: irows } = await db
        .from("interactions")
        .select("project_id")
        .eq("interaction_id", iid)
        .limit(1);

      if (irows?.[0]?.project_id) {
        addCandidate(irows[0].project_id, "interactions_existing_project");
        sources_used.push("interactions_existing_project");
      }
    }

    // SOURCE 4-6: Transcript-based sources
    if (n.transcript) {
      // Clean transcript for matching (strip speaker labels)
      const transcriptClean = stripSpeakerLabels(n.transcript);
      const transcriptLower = transcriptClean.toLowerCase();

      // Fetch all projects + aliases for matching
      const { data: projects } = await db.from("projects").select(
        "id, name, aliases, city, address",
      );
      const { data: aliasRows } = await db.from("v_project_alias_lookup")
        .select("project_id, alias");

      // Build alias map
      const aliasByProject = new Map<string, string[]>();
      for (const r of (aliasRows || [])) {
        if (!r.project_id || !r.alias) continue;
        if (!aliasByProject.has(r.project_id)) {
          aliasByProject.set(r.project_id, []);
        }
        aliasByProject.get(r.project_id)!.push(r.alias);
      }

      // SOURCE 4: Name/alias/location matches in transcript (with word boundaries)
      if (projects) {
        sources_used.push("transcript_scan");
        for (const p of projects) {
          if (!p.id || !p.name) continue;

          // Collect all searchable terms for this project
          const terms: string[] = [p.name];
          const fromAliasTable = aliasByProject.get(p.id) || [];
          terms.push(...fromAliasTable);
          if (Array.isArray(p.aliases)) terms.push(...p.aliases);
          if (p.city) terms.push(p.city);
          if (p.address) terms.push(p.address);

          const normalizedTerms = normalizeAliasTerms(terms);

          for (const term of normalizedTerms) {
            const termLower = term.toLowerCase();
            const idx = findTermInText(transcriptLower, termLower);
            if (idx >= 0) {
              // Found a match with word boundaries!
              const matchType = fromAliasTable.some((a) => a.toLowerCase() === termLower)
                ? "alias_match"
                : (p.name.toLowerCase() === termLower ? "name_match" : "location_match");

              const cur = candidatesById.get(p.id) || {
                project_id: p.id,
                assigned: false,
                affinity_weight: 0,
                sources: [],
                alias_matches: [],
              };
              if (!cur.sources.includes("transcript_scan")) {
                cur.sources.push("transcript_scan");
              }
              cur.alias_matches.push({ term, match_type: matchType });
              candidatesById.set(p.id, cur);
            }
          }
        }
      }

      // SOURCE 5: Try RPC scan_transcript_for_projects (if available)
      try {
        const { data: scanData, error: scanErr } = await db.rpc(
          "scan_transcript_for_projects",
          {
            transcript_text: n.transcript,
            similarity_threshold: 0.4,
          },
        );

        if (!scanErr && scanData?.length) {
          sources_used.push("rpc_scan_transcript_for_projects");
          for (const r of scanData) {
            const pid = r.project_id || r.projectId;
            if (pid) {
              const score = Number(r.score || r.similarity || 0) || 0;
              addCandidate(pid, "rpc_scan_transcript_for_projects", score);

              // Add as alias match evidence
              const cur = candidatesById.get(pid);
              if (cur && r.matched_term) {
                cur.alias_matches.push({
                  term: r.matched_term,
                  match_type: "db_scan",
                });
              }
            }
          }
        }
      } catch { /* RPC may not exist, ignore */ }

      // SOURCE 6: Try RPC expand_candidates_from_mentions (non-floater contacts)
      try {
        const { data: mentionData, error: mentionErr } = await db.rpc(
          "expand_candidates_from_mentions",
          {
            transcript_text: n.transcript,
          },
        );

        if (!mentionErr && mentionData?.length) {
          sources_used.push("rpc_expand_candidates_from_mentions");
          for (const r of mentionData) {
            const pid = r.project_id || r.projectId;
            if (pid) {
              const affinity = Number(r.contact_affinity || r.affinity || 0.9) || 0.9;
              addCandidate(pid, "mentioned_contact_affinity", affinity);

              // Add as alias match evidence
              const cur = candidatesById.get(pid);
              if (cur && r.mentioned_contact) {
                cur.alias_matches.push({
                  term: r.mentioned_contact,
                  match_type: "mentioned_contact_affinity",
                });
              }
            }
          }
        }
      } catch { /* RPC may not exist, ignore */ }
    }

    // ========================================
    // V3 PORTED: RANKING FORMULA
    // ========================================
    // Fetch project names for candidates
    const candidateIds = Array.from(candidatesById.keys());
    const projectNameById = new Map<string, string>();

    if (candidateIds.length) {
      const { data: prows } = await db
        .from("projects")
        .select("id, name")
        .in("id", candidateIds);

      if (prows) {
        for (const p of prows) {
          if (p.id && p.name) projectNameById.set(p.id, p.name);
        }
      }
    }

    // Calculate rank scores and sort
    const rankedCandidates: CandidateProject[] = [];

    for (const [pid, meta] of candidatesById) {
      const isExistingProject = meta.sources.includes(
        "interactions_existing_project",
      );
      const hasMentionedContact = meta.sources.includes(
        "mentioned_contact_affinity",
      );
      const hasAliasEvidence = meta.alias_matches.length > 0;

      // V3 ranking formula (from context_assembly v4.0.22)
      // - assigned via project_contacts: +100
      // - existing_project with evidence: +80, without evidence: +20
      // - mentioned non-floater contact: +40
      // - affinity weight: +min(weight*10, 50)
      // - alias/name matches: +min(count*20, 60)
      const rank_score = (meta.assigned ? 100 : 0) +
        (isExistingProject ? (hasAliasEvidence ? 80 : 20) : 0) +
        (hasMentionedContact ? 40 : 0) +
        Math.min(Math.max(meta.affinity_weight * 10, 0), 50) +
        Math.min(meta.alias_matches.length * 20, 60);

      rankedCandidates.push({
        project_id: pid,
        project_name: projectNameById.get(pid) || pid,
        assigned: meta.assigned,
        affinity_weight: meta.affinity_weight,
        sources: meta.sources,
        alias_matches: meta.alias_matches,
        rank_score,
      });
    }

    // Sort: assigned first, then by alias matches, then affinity, then rank_score
    rankedCandidates.sort((a, b) => {
      if (a.assigned !== b.assigned) {
        return (b.assigned ? 1 : 0) - (a.assigned ? 1 : 0);
      }
      if (b.alias_matches.length !== a.alias_matches.length) {
        return b.alias_matches.length - a.alias_matches.length;
      }
      if (b.affinity_weight !== a.affinity_weight) {
        return b.affinity_weight - a.affinity_weight;
      }
      return b.rank_score - a.rank_score;
    });

    // ========================================
    // SELECT WINNER
    // ========================================
    if (rankedCandidates.length > 0) {
      const winner = rankedCandidates[0];
      project_id = winner.project_id;
      project_name = winner.project_name;
      project_source = winner.sources.join("+");

      // Confidence based on evidence strength
      const maxScore = 100 + 80 + 40 + 50 + 60; // 330 theoretical max
      project_confidence = Math.min(winner.rank_score / maxScore, 0.99);

      // Boost confidence if multiple sources agree
      if (winner.sources.length >= 3) {
        project_confidence = Math.min(project_confidence + 0.1, 0.99);
      }
      if (winner.alias_matches.length >= 2) {
        project_confidence = Math.min(project_confidence + 0.05, 0.99);
      }
    }

    // GATE
    const g = m4(n);

    // CALLS_RAW
    const { data: cr } = await db.from("calls_raw").upsert({
      interaction_id: iid,
      channel: "call",
      direction: n.direction || null,
      owner_phone: n.from_phone || null,
      other_party_phone: phone || null,
      event_at_utc: n.event_at_utc || null,
      transcript: n.transcript || null,
      recording_url: n.recording_url || n.beside_note_url || null,
      pipeline_version: "v3.9",
      raw_snapshot_json: {
        run_id,
        v: "v3.9.0",
        gate: g.decision,
        contact_id,
        project_id,
        project_source,
        project_confidence,
        candidate_count: rankedCandidates.length,
        top_candidates: rankedCandidates.slice(0, 5).map((c) => ({
          id: c.project_id,
          name: c.project_name,
          score: c.rank_score,
          sources: c.sources,
          matches: c.alias_matches.length,
        })),
        sources_used,
      },
    }, { onConflict: "interaction_id" }).select("id").single();
    if (cr) cr_uuid = cr.id;

    // INTERACTIONS
    if (g.decision === "PASS" || g.decision === "NEEDS_REVIEW") {
      await db.from("interactions").upsert({
        interaction_id: iid,
        channel: "call",
        contact_id: contact_id || null,
        contact_name: contact_name || null,
        contact_phone: phone || null,
        owner_phone: n.from_phone || null,
        project_id: project_id || null,
        event_at_utc: n.event_at_utc || null,
        needs_review: g.decision === "NEEDS_REVIEW",
        review_reasons: g.reasons,
        project_attribution_confidence: project_confidence,
        transcript_chars: n.transcript?.length || 0,
      }, { onConflict: "interaction_id" });
    }

    // CONTACT STATS (optional, ignore errors)
    if (contact_id) {
      try {
        await db.rpc("update_contact_interaction_stats", {
          p_contact_id: contact_id,
        });
      } catch {}
    }

    // AUDIT FINAL
    if (audit_id) {
      await db.from("event_audit").update({
        gate_status: g.decision,
        gate_reasons: g.reasons,
        persisted_to_calls_raw: !!cr_uuid,
        calls_raw_uuid: cr_uuid,
      }).eq("id", audit_id);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        run_id,
        interaction_id: iid,
        decision: g.decision,
        reasons: g.reasons,
        contact_id,
        contact_name,
        project_id,
        project_name,
        project_source,
        project_confidence,
        candidate_count: rankedCandidates.length,
        top_candidates: rankedCandidates.slice(0, 3).map((c) => ({
          id: c.project_id,
          name: c.project_name,
          score: c.rank_score,
        })),
        sources_used,
        audit_id,
        cr_uuid,
        ms: Date.now() - t0,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e: any) {
    if (audit_id) {
      await db.from("event_audit").update({
        gate_status: "ERROR",
        gate_reasons: [e.message || "unknown"],
      }).eq("id", audit_id);
    }
    return new Response(
      JSON.stringify({
        ok: false,
        run_id,
        interaction_id: iid,
        error: e.message,
        ms: Date.now() - t0,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
