/**
 * context-assembly Edge Function v1.9.0
 * Assembles LLM-ready context_package from span_id (SPAN-FIRST)
 *
 * @version 1.9.0
 * @date 2026-02-13
 * @purpose Provide rich context for AI Router project attribution
 * @port 6-source candidate collection from process-call v3.9.6
 *
 * CORE PRINCIPLE: span_id is the unit of truth. Calls are containers only.
 *
 * v1.9.0 Changes (AI-ready Geo Signal Enrichment):
 * - NEW: Candidate evidence now includes geo_signal summary:
 *   { score, dominant_role, role_counts, place_count }
 * - NEW: Geo scoring stays weak by design (never sufficient for auto-assign)
 * - NEW: Role-aware geo aggregation (destination/origin/proximity) per project
 *
 * v1.8.0 Changes (Journal Context Poisoning Fix):
 * - NEW: journal claims/loops are contact-scoped (same contact_id OR same phone)
 * - NEW: null-contact calls skip journal context entirely to avoid unanchored leakage
 *
 * v1.5.0 Changes (Contact Fanout Integration — DATA-9 D4 spec):
 * - REPLACED: contacts.floats_between_projects boolean → contact_fanout table lookup
 * - NEW: context_package.contact.fanout_class (anchored|semi_anchored|drifter|floater|unknown)
 * - NEW: context_package.contact.effective_fanout (integer project count)
 * - PRESERVED: floater_flag for backwards compat (derived from fanout_class)
 *
 * v1.7.0 Changes (Continuity Bundle):
 * - NEW: continuity_links array linking back-to-back calls within 48h
 * - Tiered evidence (project mention, callback phrase, recency) with floater rule
 *
 * v1.6.0 Changes (Gmail Context Lookup):
 * - NEW: calls gmail-context-lookup edge function (bounded, fail-open)
 * - NEW: context_package.email_context (bounded metadata, no free-text snippets)
 * - NEW: context_package.email_lookup_meta (receipt-friendly lookup metadata)
 *
 * v1.4.0 Changes (Journal/World Model integration):
 * - NEW: journal-derived project state injected into context package
 * - For each candidate project, fetches active journal_claims and open_loops
 * - New field: context_package.project_journal (per-project state summaries)
 *
 * v1.2.0 Changes (PR-7 Phase 2: Enroute Detection):
 * - VERB-DRIVEN role tagging: destination/origin/proximity
 * - Inserts detected place mentions into span_place_mentions
 * - POLICY (STRAT-1 BLOCK): Role is ONLY assigned via explicit verbs
 * - Single place without verb = "proximity" (NEVER inferred direction)
 *
 * v1.1.0 Changes (PR-7: Geo Candidate Assist):
 * - SOURCE 7: geo proximity candidates from project_geo + geo_places
 * - Geo is a WEAK signal only (source='geo_proximity')
 * - Never sufficient for auto-assign; adds nearby projects as candidates
 *
 * Input:
 *   - span_id: string (required) - PRIMARY key for context assembly
 *   - interaction_id + span_index: (debug convenience) - resolves to span_id first
 *
 * Output:
 *   - context_package JSON with meta, span, contact, candidates, place_mentions, project_journal,
 *     email_context, email_lookup_meta
 *
 * AUTH:
 * - Accepts service role JWT (verify_jwt=false in config)
 * - Also accepts X-Edge-Secret for internal function-to-function calls
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ASSEMBLY_VERSION = "v1.9.0"; // v1.9.0: AI-ready geo signal enrichment
const SELECTION_RULES_VERSION = "v1.0.0";
const MAX_CANDIDATES = 8;
const MAX_TRANSCRIPT_CHARS = 8000;
const MAX_ALIAS_TERMS_PER_PROJECT = 25;
const GMAIL_LOOKUP_DEFAULT_LOOKBACK_DAYS = 30;
const GMAIL_LOOKUP_DEFAULT_MAX_RESULTS = 5;
const GMAIL_LOOKUP_TIMEOUT_MS = 8000;

// Geo candidate constants
const GEO_MAX_DISTANCE_KM = 50; // Only consider projects within 50km
const GEO_MAX_CANDIDATES = 5; // Cap geo candidates to prevent flooding

// Continuity bundle constants
const CONTINUITY_LOOKBACK_HOURS = 48;
const CONTINUITY_MAX_PRIOR_CALLS = 5;
const CONTINUITY_FLOATER_GAP_HOURS = 4;
const CALLBACK_PHRASES = [
  "calling you back",
  "returning your call",
  "missed your call",
  "following up",
  "as we discussed",
  "like we talked about",
];

// PR-11: Project status filter - only include active client projects
const VALID_PROJECT_STATUSES = ["active", "warranty", "estimating"];
// PR-11 (STRAT TURN14): Filter by project_kind to exclude internal/owner projects
const VALID_PROJECT_KIND = "client";

// ============================================================
// ADMIN ALLOWLIST (PR-10 hardening)
// Hard-coded admin user IDs as second-layer gate
// REQUIRED: At least one of ADMIN_USER_IDS or ALLOWED_EMAILS must match
// ============================================================
const ADMIN_USER_IDS: string[] = [
  // Add Supabase auth.users.id values here
  // Example: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
];

// ============================================================
// ENROUTE VERB PATTERNS (STRAT-1 POLICY: VERB-DRIVEN ONLY)
// ============================================================
// POLICY: Role tagging is DETERMINISTIC and VERB-DRIVEN
// - "destination" requires explicit destination verbs
// - "origin" requires explicit origin verbs
// - Single place mention WITHOUT verb = "proximity" (NO direction inferred)
// - NEVER infer direction from a single place without explicit verb

const DESTINATION_VERBS = [
  "headed to",
  "heading to",
  "going to",
  "on my way to",
  "on the way to",
  "driving to",
  "heading over to",
  "headed over to",
  "going over to",
  "en route to",
  "enroute to",
];

const ORIGIN_VERBS = [
  "coming from",
  "came from",
  "leaving",
  "left from",
  "left",
  "back from",
  "returning from",
  "just left",
  "driving from",
  "on my way from",
];

// ============================================================
// TYPES
// ============================================================

interface AliasMatch {
  term: string;
  match_type: string;
  snippet?: string;
}

type PlaceRole = "proximity" | "origin" | "destination";

interface GeoSignal {
  // Weak signal score (0.05-0.55): useful for AI tie-breaking, never for solo auto-assign.
  score: number;
  dominant_role: PlaceRole;
  role_counts: Record<PlaceRole, number>;
  place_count: number;
}

interface CandidateEvidence {
  sources: string[];
  affinity_weight: number;
  assigned: boolean;
  alias_matches: AliasMatch[];
  geo_distance_km?: number;
  geo_signal?: GeoSignal;
  weak_only?: boolean; // true if ALL alias evidence is weak (first-name-only, short token)
}

interface Candidate {
  project_id: string;
  project_name: string;
  address: string | null;
  client_name: string | null;
  aliases: string[];
  status: string | null;
  phase: string | null;
  evidence: CandidateEvidence;
}

interface RecentProject {
  project_id: string;
  project_name: string;
  last_seen: string | null;
}

interface PlaceMention {
  place_name: string;
  geo_place_id: string | null;
  lat: number | null;
  lon: number | null;
  role: PlaceRole;
  trigger_verb: string | null;
  char_offset: number;
  snippet: string;
}

// v1.4.0: Journal-derived project state
interface JournalClaim {
  claim_type: string;
  claim_text: string;
  epistemic_status: string;
  created_at: string;
}

interface JournalOpenLoop {
  loop_type: string;
  description: string;
  status: string;
}

interface ProjectJournalState {
  project_id: string;
  active_claims_count: number;
  recent_claims: JournalClaim[]; // Last 5 active claims
  open_loops: JournalOpenLoop[]; // Open loops for this project
  last_journal_activity: string | null; // Timestamp of most recent claim
}

interface EmailContextItem {
  message_id: string;
  thread_id: string | null;
  date: string | null;
  from: string | null;
  to: string | null;
  subject: string | null;
  subject_keywords: string[];
  project_mentions: string[];
  mentioned_project_ids: string[];
  amounts_mentioned: string[];
  evidence_locator: string;
}

interface EmailLookupMeta {
  step: string;
  source: string | null;
  contact_id: string | null;
  query: string | null;
  date_range: string | null;
  results_count: number;
  returned_count: number;
  cached: boolean;
  lookup_ms: number | null;
  gmail_api_calls: number;
  auth_mode: string | null;
  warnings: string[];
  truncation: string[];
}

interface ContextPackage {
  meta: {
    assembly_version: string;
    selection_rules_version: string;
    span_id: string;
    interaction_id: string;
    assembled_at_utc: string;
    truncations: string[];
    warnings: string[];
    sources_used: string[];
  };
  span: {
    start_ms: number | null;
    end_ms: number | null;
    transcript_text: string;
    words?: any[];
  };
  contact: {
    contact_id: string | null;
    contact_name: string | null;
    phone_e164_last4: string | null;
    floater_flag: boolean; // Backwards compat: derived from fanout_class
    fanout_class: string; // v1.5.0: anchored|semi_anchored|drifter|floater|unknown
    effective_fanout: number; // v1.5.0: number of active projects
    recent_projects: RecentProject[];
  };
  candidates: Candidate[];
  place_mentions: PlaceMention[];
  project_journal: ProjectJournalState[]; // v1.4.0: journal-derived state per candidate project
  email_context: EmailContextItem[];
  email_lookup_meta: EmailLookupMeta | null;
  continuity_links: ContinuityLink[];
}

interface ContinuityLink {
  prior_interaction_id: string;
  prior_project_id: string | null;
  prior_project_name: string | null;
  prior_event_at_utc: string | null;
  gap_minutes: number;
  tier: "TIER_1" | "TIER_2" | "TIER_3";
  evidence: {
    reason: string;
    spans: string[];
    callback_phrase_hits: string[];
  };
}

// ============================================================
// UTILITIES
// ============================================================

/** Strip speaker labels from transcript to avoid false alias matches */
function stripSpeakerLabels(text: string): string {
  return (text || "").replace(/(^|\n)\s*[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s*:/g, "$1");
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

/** PHONETIC-ADJACENT-ONLY: Classify whether an alias match is strong or weak.
 *  - "strong": exact project name, multi-word alias, last-name match, or location
 *  - "weak": single short first-name-only token with no corroboration */
function classifyMatchStrength(
  term: string,
  matchType: string,
  projectName: string,
): "strong" | "weak" {
  const termLower = term.toLowerCase();
  const nameLower = projectName.toLowerCase();

  // Exact project name match is always strong
  if (termLower === nameLower || matchType === "exact_project_name" || matchType === "name_match") return "strong";

  // Multi-word terms are strong (full name, address, etc.)
  if (term.trim().includes(" ")) return "strong";

  // Location matches are strong
  if (matchType === "city_or_location" || matchType === "location_match") return "strong";

  // Check if this is a last-name component match (strong)
  const nameParts = nameLower.split(/\s+/);
  if (nameParts.length >= 2) {
    const lastName = nameParts[nameParts.length - 1];
    if (termLower === lastName) return "strong";
  }

  // Single-word alias match >= 6 chars is strong (distinctive enough)
  if (term.length >= 6 && (matchType === "alias" || matchType === "alias_match")) return "strong";

  // Everything else (short single-word, first-name-only, db_scan short tokens) = weak
  return "weak";
}

/** Extract snippet around a match position */
function snippetAround(text: string, idx: number, termLen: number, radius = 40): string {
  if (!text || idx < 0) return "";
  const start = Math.max(0, idx - radius);
  const end = Math.min(text.length, idx + termLen + radius);
  let snippet = text.slice(start, end).replace(/\s+/g, " ").trim();
  if (start > 0) snippet = "..." + snippet;
  if (end < text.length) snippet = snippet + "...";
  return snippet.slice(0, 100);
}

function normalizePhone(phone: string | null | undefined): string | null {
  const digits = (phone || "").replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 11 && digits.startsWith("1")) return digits.slice(1);
  if (digits.length > 10) return digits.slice(-10);
  return digits;
}

function matchesJournalSourceContact(
  currentContactId: string | null,
  currentPhone: string | null,
  sourceContactId: string | null | undefined,
  sourcePhone: string | null | undefined,
): boolean {
  if (currentContactId && sourceContactId && currentContactId === sourceContactId) {
    return true;
  }
  const cur = normalizePhone(currentPhone);
  const src = normalizePhone(sourcePhone);
  if (!cur || !src) return false;
  return cur === src || cur.slice(-4) === src.slice(-4);
}

/** Smart truncation: window around evidence to preserve anchors */
function smartTruncate(
  transcript: string,
  matchPositions: number[],
  maxChars: number,
): { text: string; truncated: boolean } {
  if (transcript.length <= maxChars) {
    return { text: transcript, truncated: false };
  }

  if (matchPositions.length === 0) {
    return { text: transcript.slice(0, maxChars) + "...", truncated: true };
  }

  const firstMatch = Math.min(...matchPositions);
  const lastMatch = Math.max(...matchPositions);
  const matchSpan = lastMatch - firstMatch;
  const windowStart = Math.max(0, firstMatch - Math.floor((maxChars - matchSpan) / 2));
  const windowEnd = Math.min(transcript.length, windowStart + maxChars);

  let text = transcript.slice(windowStart, windowEnd);
  if (windowStart > 0) text = "..." + text;
  if (windowEnd < transcript.length) text = text + "...";

  return { text, truncated: true };
}

/** Haversine distance in km between two lat/lon points */
function haversineDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const R = 6371;
  const toRad = (deg: number) => deg * Math.PI / 180;

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);

  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function emptyRoleCounts(): Record<PlaceRole, number> {
  return { proximity: 0, origin: 0, destination: 0 };
}

function dominantRoleFromCounts(counts: Record<PlaceRole, number>): PlaceRole {
  const destination = counts.destination || 0;
  const origin = counts.origin || 0;
  const proximity = counts.proximity || 0;

  // Tie-break policy prefers directional roles over proximity.
  if (destination >= origin && destination >= proximity) return "destination";
  if (origin >= destination && origin >= proximity) return "origin";
  return "proximity";
}

function computeGeoWeakScore(
  minDistanceKm: number,
  roleCounts: Record<PlaceRole, number>,
  placeCount: number,
): number {
  // Base distance signal: 0..0.35 across the 50km window.
  const normalizedDistance = Math.max(0, Math.min(1, 1 - (minDistanceKm / GEO_MAX_DISTANCE_KM)));
  const distanceScore = normalizedDistance * 0.35;

  // Directional phrasing adds weak corroboration, never enough to stand alone.
  const directionalHits = (roleCounts.destination || 0) + (roleCounts.origin || 0);
  const roleBoost = directionalHits > 0 ? 0.12 : 0;

  // Multiple distinct place mentions can reinforce confidence slightly.
  const placeBoost = Math.min(0.08, Math.max(0, placeCount - 1) * 0.02);

  // Always keep geo in weak band.
  const raw = 0.05 + distanceScore + roleBoost + placeBoost;
  return Math.max(0.05, Math.min(0.55, raw));
}

/** Find callback phrases and return snippets (<=80 chars) around them */
function findCallbackPhraseSpans(
  transcript: string,
  transcriptLower: string,
): string[] {
  const spans: string[] = [];
  for (const phrase of CALLBACK_PHRASES) {
    const phraseLower = phrase.toLowerCase();
    const idx = transcriptLower.indexOf(phraseLower);
    if (idx >= 0) {
      const snippet = snippetAround(transcript, idx, phrase.length, 60).slice(0, 80);
      spans.push(snippet);
      if (spans.length >= 5) break;
    }
  }
  return spans;
}

/**
 * VERB-DRIVEN ROLE DETECTION
 * POLICY (STRAT-1 BLOCK):
 * - Role is ONLY assigned via explicit verbs
 * - Single place without verb = "proximity"
 * - NEVER infer direction from a single place
 *
 * @param transcriptLower - Lowercased transcript
 * @param placeIdx - Character index of place mention
 * @param placeName - Name of the place
 * @returns { role, trigger_verb } - Role and the verb that triggered it
 */
function detectPlaceRole(
  transcriptLower: string,
  placeIdx: number,
  placeName: string,
): { role: PlaceRole; trigger_verb: string | null } {
  // Look in a window before the place mention for verb patterns
  const VERB_WINDOW = 60; // Characters before place to search for verbs
  const windowStart = Math.max(0, placeIdx - VERB_WINDOW);
  const windowText = transcriptLower.slice(windowStart, placeIdx + placeName.length);

  // Check destination verbs first (more specific patterns)
  for (const verb of DESTINATION_VERBS) {
    const verbIdx = windowText.indexOf(verb);
    if (verbIdx >= 0) {
      // Verify verb appears BEFORE the place (not after)
      const verbEndPos = windowStart + verbIdx + verb.length;
      if (verbEndPos <= placeIdx + 5) { // Allow small gap
        return { role: "destination", trigger_verb: verb };
      }
    }
  }

  // Check origin verbs
  for (const verb of ORIGIN_VERBS) {
    const verbIdx = windowText.indexOf(verb);
    if (verbIdx >= 0) {
      const verbEndPos = windowStart + verbIdx + verb.length;
      if (verbEndPos <= placeIdx + 5) {
        return { role: "origin", trigger_verb: verb };
      }
    }
  }

  // No verb found = proximity only (NEVER infer direction)
  return { role: "proximity", trigger_verb: null };
}

// ============================================================
// MAIN HANDLER
// ============================================================

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // ========================================
  // AUTH GATE: X-Edge-Secret (internal) OR JWT (external)
  // v1.4.1: Added X-Edge-Secret path for function-to-function calls
  //         (segment-call sends X-Edge-Secret, not JWT)
  // ========================================
  const edgeSecretHeader = req.headers.get("X-Edge-Secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");
  const authHeader = req.headers.get("Authorization");

  // Path 1: Internal function-to-function via X-Edge-Secret
  const hasValidEdgeSecret = !!(expectedSecret && edgeSecretHeader && edgeSecretHeader === expectedSecret);

  let body: any;
  try {
    body = await req.json();
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

  // Path 2: External JWT auth (only if no valid edge secret)
  if (!hasValidEdgeSecret) {
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "missing_auth", hint: "X-Edge-Secret or Authorization: Bearer <token> required" }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Verify JWT is valid (will fail if token invalid/expired)
    const anonClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: authErr } = await anonClient.auth.getUser();
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "invalid_token", detail: authErr?.message }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ========================================
    // AUTHORIZATION GATE (PR-10 hardening)
    // Two-layer check: ADMIN_USER_IDS (hard-coded) OR ALLOWED_EMAILS (env)
    // At least one gate must be configured; user must pass at least one
    // ========================================
    const allowedEmails = (Deno.env.get("ALLOWED_EMAILS") || "").split(",").map(
      (e) => e.trim().toLowerCase(),
    ).filter(Boolean);

    const userEmail = (user.email || "").toLowerCase();
    const userId = user.id;

    // Check if user passes either gate
    const isAdmin = ADMIN_USER_IDS.length > 0 && ADMIN_USER_IDS.includes(userId);
    const isAllowedEmail = allowedEmails.length > 0 && allowedEmails.includes(userEmail);

    // At least one gate must be configured
    if (ADMIN_USER_IDS.length === 0 && allowedEmails.length === 0) {
      return new Response(
        JSON.stringify({ error: "config_error", hint: "Neither ADMIN_USER_IDS nor ALLOWED_EMAILS configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    // User must pass at least one gate
    if (!isAdmin && !isAllowedEmail) {
      return new Response(JSON.stringify({ error: "forbidden", hint: "User not authorized" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  const truncations: string[] = [];
  const warnings: string[] = [];
  const sources_used: string[] = [];

  try {
    // ========================================
    // RESOLVE SPAN_ID (span-first)
    // ========================================
    let span_id: string | null = body.span_id || null;
    let interaction_id: string | null = null;

    if (!span_id && body.interaction_id) {
      const span_index = body.span_index ?? 0;
      // POLICY: Active spans only (is_superseded=false)
      const { data: spanRow } = await db
        .from("conversation_spans")
        .select("id, interaction_id")
        .eq("interaction_id", body.interaction_id)
        .eq("span_index", span_index)
        .eq("is_superseded", false)
        .single();

      if (spanRow) {
        span_id = spanRow.id;
        interaction_id = spanRow.interaction_id;
      }
    }

    if (!span_id) {
      return new Response(
        JSON.stringify({
          error: "missing_span_id",
          hint: "Provide span_id directly, or interaction_id + span_index to resolve",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // ========================================
    // FETCH SPAN DATA
    // ========================================
    const { data: span, error: spanErr } = await db
      .from("conversation_spans")
      .select("id, interaction_id, transcript_segment, time_start_sec, time_end_sec, char_start, char_end")
      .eq("id", span_id)
      .single();

    if (spanErr || !span) {
      return new Response(
        JSON.stringify({
          error: "span_not_found",
          span_id,
          db_error: spanErr?.message,
        }),
        {
          status: 404,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    interaction_id = span.interaction_id;
    const transcript_text = span.transcript_segment || "";
    const start_ms = span.time_start_sec != null ? span.time_start_sec * 1000 : null;
    const end_ms = span.time_end_sec != null ? span.time_end_sec * 1000 : null;

    // Fetch words from transcripts_comparison
    let words: any[] | undefined;
    const { data: tc } = await db
      .from("transcripts_comparison")
      .select("words")
      .eq("interaction_id", interaction_id)
      .not("words", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (tc?.words && Array.isArray(tc.words)) {
      words = tc.words;
    }

    // ========================================
    // FETCH CONTACT DATA
    // ========================================
    let contact_id: string | null = null;
    let contact_name: string | null = null;
    let contact_phone: string | null = null;
    let event_at_utc: string | null = null;
    let fanout_class = "unknown";
    let effective_fanout = 0;
    let floater_flag = false; // Backwards compat: derived from fanout_class

    const { data: interaction } = await db
      .from("interactions")
      .select("contact_id, contact_name, contact_phone, event_at_utc, project_id")
      .eq("interaction_id", interaction_id)
      .single();

    if (interaction) {
      contact_id = interaction.contact_id;
      contact_name = interaction.contact_name;
      contact_phone = interaction.contact_phone;
      event_at_utc = interaction.event_at_utc;
    }

    // v1.5.0: Fetch fanout data from contact_fanout table (DATA-9 D4 spec)
    // Replaces the boolean contacts.floats_between_projects
    if (contact_id) {
      const { data: fanoutRow } = await db
        .from("contact_fanout")
        .select("fanout_class, effective_fanout")
        .eq("contact_id", contact_id)
        .single();

      if (fanoutRow) {
        fanout_class = fanoutRow.fanout_class || "unknown";
        effective_fanout = fanoutRow.effective_fanout || 0;
        // Backwards compat: floater_flag = true if floater or drifter (per DATA-9 D4 spec)
        floater_flag = fanout_class === "floater" || fanout_class === "drifter";
      } else {
        // Fallback: if no fanout row, check legacy boolean
        const { data: contact } = await db
          .from("contacts")
          .select("floats_between_projects")
          .eq("id", contact_id)
          .single();

        if (contact) {
          floater_flag = !!contact.floats_between_projects;
          // Infer fanout_class from legacy flag
          fanout_class = floater_flag ? "floater" : "unknown";
        }
      }
    }

    const recent_projects: RecentProject[] = [];
    if (contact_id) {
      const { data: affRows } = await db
        .from("correspondent_project_affinity")
        .select("project_id, last_interaction_at")
        .eq("contact_id", contact_id)
        .order("last_interaction_at", { ascending: false })
        .limit(5);

      if (affRows?.length) {
        const projectIds = affRows.map((r) => r.project_id).filter(Boolean);
        const { data: prows } = await db
          .from("projects")
          .select("id, name")
          .in("id", projectIds);

        const nameById = new Map((prows || []).map((p) => [p.id, p.name]));

        for (const r of affRows) {
          if (r.project_id) {
            recent_projects.push({
              project_id: r.project_id,
              project_name: nameById.get(r.project_id) || r.project_id,
              last_seen: r.last_interaction_at || null,
            });
          }
        }
      }
    }

    const phone_e164_last4 = contact_phone ? contact_phone.slice(-4) : null;
    let email_context: EmailContextItem[] = [];
    let email_lookup_meta: EmailLookupMeta | null = null;
    let continuity_links: ContinuityLink[] = [];

    // ========================================
    // SOURCE 8: Gmail context lookup (fail-open)
    // - Runs only when a contact is known.
    // - Returns bounded metadata (<=5 messages, no free-text snippets).
    // ========================================
    if (contact_id) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const gmailLookupUrl = Deno.env.get("GMAIL_CONTEXT_LOOKUP_URL") ||
        (supabaseUrl ? `${supabaseUrl}/functions/v1/gmail-context-lookup` : null);

      if (gmailLookupUrl) {
        const lookupHeaders: Record<string, string> = {
          "Content-Type": "application/json",
        };

        if (expectedSecret) {
          lookupHeaders["X-Edge-Secret"] = expectedSecret;
        } else if (authHeader?.startsWith("Bearer ")) {
          lookupHeaders["Authorization"] = authHeader;
        }

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), GMAIL_LOOKUP_TIMEOUT_MS);
        try {
          const gmailResp = await fetch(gmailLookupUrl, {
            method: "POST",
            headers: lookupHeaders,
            body: JSON.stringify({
              contact_id,
              interaction_id,
              span_id,
              lookback_days: GMAIL_LOOKUP_DEFAULT_LOOKBACK_DAYS,
              max_results: GMAIL_LOOKUP_DEFAULT_MAX_RESULTS,
              source: "context-assembly",
            }),
            signal: controller.signal,
          });

          if (!gmailResp.ok) {
            warnings.push(`gmail_lookup_http_${gmailResp.status}`);
          } else {
            const gmailPayload = await gmailResp.json().catch(() => null);
            if (gmailPayload?.ok) {
              email_context = Array.isArray(gmailPayload.email_context)
                ? gmailPayload.email_context as EmailContextItem[]
                : [];
              email_lookup_meta = gmailPayload.email_lookup_meta &&
                  typeof gmailPayload.email_lookup_meta === "object"
                ? gmailPayload.email_lookup_meta as EmailLookupMeta
                : null;
              sources_used.push("gmail_context_lookup");
              if (email_lookup_meta?.warnings?.length) {
                warnings.push(...email_lookup_meta.warnings.map((w) => `gmail:${w}`));
              }
              if (email_lookup_meta?.truncation?.length) {
                truncations.push(...email_lookup_meta.truncation.map((t) => `gmail:${t}`));
              }
            } else {
              warnings.push("gmail_lookup_invalid_payload");
            }
          }
        } catch (error: any) {
          if (error?.name === "AbortError") {
            warnings.push("gmail_lookup_timeout");
          } else {
            warnings.push(`gmail_lookup_exception:${String(error?.message || error).slice(0, 100)}`);
          }
        } finally {
          clearTimeout(timeoutId);
        }
      } else {
        warnings.push("gmail_lookup_url_missing");
      }
    }

    // ========================================
    // 7-SOURCE CANDIDATE COLLECTION
    // (plus Source 8 Gmail context lookup above)
    // ========================================
    const candidatesById = new Map<string, {
      project_id: string;
      assigned: boolean;
      affinity_weight: number;
      sources: string[];
      alias_matches: AliasMatch[];
      geo_distance_km?: number;
      geo_signal?: GeoSignal;
    }>();

    const addCandidate = (
      pid: string,
      source: string,
      weight = 0,
      geo_distance_km?: number,
      geo_signal?: GeoSignal,
    ) => {
      if (!pid) return;
      const cur = candidatesById.get(pid) || {
        project_id: pid,
        assigned: false,
        affinity_weight: 0,
        sources: [],
        alias_matches: [],
      };
      if (!cur.sources.includes(source)) cur.sources.push(source);
      if (weight > 0) cur.affinity_weight = Math.max(cur.affinity_weight, weight);
      if (geo_distance_km !== undefined) {
        cur.geo_distance_km = cur.geo_distance_km !== undefined
          ? Math.min(cur.geo_distance_km, geo_distance_km)
          : geo_distance_km;
      }
      if (geo_signal) {
        if (!cur.geo_signal) {
          cur.geo_signal = geo_signal;
        } else {
          const mergedCounts: Record<PlaceRole, number> = {
            proximity: (cur.geo_signal.role_counts.proximity || 0) + (geo_signal.role_counts.proximity || 0),
            origin: (cur.geo_signal.role_counts.origin || 0) + (geo_signal.role_counts.origin || 0),
            destination: (cur.geo_signal.role_counts.destination || 0) +
              (geo_signal.role_counts.destination || 0),
          };
          cur.geo_signal = {
            score: Math.max(cur.geo_signal.score, geo_signal.score),
            dominant_role: dominantRoleFromCounts(mergedCounts),
            role_counts: mergedCounts,
            place_count: Math.max(cur.geo_signal.place_count, geo_signal.place_count),
          };
        }
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
            if (!cur.sources.includes("project_contacts")) cur.sources.push("project_contacts");
            candidatesById.set(r.project_id, cur);
          }
        }
      }
    }

    // SOURCE 2: correspondent_project_affinity
    if (contact_id) {
      const { data: affRows } = await db
        .from("correspondent_project_affinity")
        .select("project_id, weight")
        .eq("contact_id", contact_id);

      if (affRows?.length) {
        sources_used.push("correspondent_project_affinity");
        for (const r of affRows) {
          if (r.project_id) {
            addCandidate(r.project_id, "correspondent_project_affinity", r.weight || 0);
          }
        }
      }
    }

    // SOURCE 3: existing_project from interactions
    {
      const { data: irows } = await db
        .from("interactions")
        .select("project_id")
        .eq("interaction_id", interaction_id)
        .limit(1);

      if (irows?.[0]?.project_id) {
        addCandidate(irows[0].project_id, "interactions_existing_project");
        sources_used.push("interactions_existing_project");
      }
    }

    const matchPositions: number[] = [];
    let callbackSpans: string[] = [];
    const projectMentionSpans: string[] = [];
    const place_mentions: PlaceMention[] = [];

    // SOURCE 4-7: Transcript-based sources
    if (transcript_text) {
      const transcriptClean = stripSpeakerLabels(transcript_text);
      const transcriptLower = transcriptClean.toLowerCase();
      callbackSpans = findCallbackPhraseSpans(transcriptClean, transcriptLower);

      // Fetch all projects + aliases for matching
      const { data: projects } = await db.from("projects").select("id, name, aliases, city, address");

      let aliasRows: Array<{ project_id: string; alias: string }> | null = null;
      try {
        const { data, error } = await db.from("v_project_alias_lookup").select("project_id, alias");
        if (!error && data) {
          aliasRows = data;
        } else if (error) {
          warnings.push("v_project_alias_lookup_missing");
        }
      } catch {
        warnings.push("v_project_alias_lookup_error");
      }

      const aliasByProject = new Map<string, string[]>();
      for (const r of (aliasRows || [])) {
        if (!r.project_id || !r.alias) continue;
        if (!aliasByProject.has(r.project_id)) aliasByProject.set(r.project_id, []);
        aliasByProject.get(r.project_id)!.push(r.alias);
      }

      // SOURCE 4: Name/alias/location matches in transcript
      if (projects) {
        sources_used.push("transcript_scan");
        for (const p of projects) {
          if (!p.id || !p.name) continue;

          const terms: string[] = [p.name];
          const fromAliasTable = aliasByProject.get(p.id) || [];
          terms.push(...fromAliasTable);
          if (Array.isArray(p.aliases)) terms.push(...p.aliases);
          if (p.city) terms.push(p.city);
          if (p.address) terms.push(p.address);

          const normalizedTerms = normalizeAliasTerms(terms).slice(0, MAX_ALIAS_TERMS_PER_PROJECT);

          for (const term of normalizedTerms) {
            const termLower = term.toLowerCase();
            const idx = findTermInText(transcriptLower, termLower);
            if (idx >= 0) {
              matchPositions.push(idx);

              const matchType = fromAliasTable.some((a) => a.toLowerCase() === termLower)
                ? "alias"
                : (p.name.toLowerCase() === termLower ? "exact_project_name" : "city_or_location");

              const cur: {
                project_id: string;
                assigned: boolean;
                affinity_weight: number;
                sources: string[];
                alias_matches: AliasMatch[];
              } = candidatesById.get(p.id) || {
                project_id: p.id,
                assigned: false,
                affinity_weight: 0,
                sources: [],
                alias_matches: [],
              };
              if (!cur.sources.includes("transcript_scan")) cur.sources.push("transcript_scan");
              const snippet = snippetAround(transcriptClean, idx, term.length);
              if (projectMentionSpans.length < 5) {
                projectMentionSpans.push(snippet.slice(0, 80));
              }
              cur.alias_matches.push({
                term,
                match_type: matchType,
                snippet,
              });
              candidatesById.set(p.id, cur);
            }
          }
        }
      }

      // SOURCE 5: RPC scan_transcript_for_projects
      try {
        const { data: scanData, error: scanErr } = await db.rpc("scan_transcript_for_projects", {
          transcript_text: transcript_text,
          similarity_threshold: 0.4,
        });

        if (!scanErr && scanData?.length) {
          sources_used.push("rpc_scan_transcript_for_projects");
          for (const r of scanData) {
            const pid = r.project_id || r.projectId;
            if (pid) {
              const score = Number(r.score || r.similarity || 0) || 0;
              addCandidate(pid, "rpc_scan_transcript_for_projects", score);

              const cur = candidatesById.get(pid);
              if (cur && r.matched_term) {
                cur.alias_matches.push({ term: r.matched_term, match_type: "db_scan" });
              }
            }
          }
        }
      } catch { /* RPC may not exist */ }

      // SOURCE 6: RPC expand_candidates_from_mentions
      try {
        const { data: mentionData, error: mentionErr } = await db.rpc("expand_candidates_from_mentions", {
          transcript_text: transcript_text,
        });

        if (!mentionErr && mentionData?.length) {
          sources_used.push("rpc_expand_candidates_from_mentions");
          for (const r of mentionData) {
            const pid = r.project_id || r.projectId;
            if (pid) {
              const affinity = Number(r.contact_affinity || r.affinity || 0.9) || 0.9;
              addCandidate(pid, "mentioned_contact_affinity", affinity);

              const cur = candidatesById.get(pid);
              if (cur && r.mentioned_contact) {
                cur.alias_matches.push({
                  term: r.mentioned_contact,
                  match_type: "mentioned_contact",
                });
              }
            }
          }
        }
      } catch { /* RPC may not exist */ }

      // ========================================
      // SOURCE 7: GEO + ENROUTE DETECTION
      // POLICY (STRAT-1 BLOCK):
      // - Role is VERB-DRIVEN only
      // - Single place without verb = "proximity"
      // - NEVER infer direction from single place
      // ========================================
      try {
        const { data: places, error: placesErr } = await db
          .from("geo_places")
          .select("id, name, state, lat, lon");

        if (!placesErr && places?.length) {
          const mentionedPlaces: Array<{
            id: string;
            name: string;
            lat: number;
            lon: number;
            char_offset: number;
            role: PlaceRole;
            trigger_verb: string | null;
            snippet: string;
          }> = [];

          for (const place of places) {
            if (!place.name || place.lat == null || place.lon == null) continue;

            const placeNameLower = place.name.toLowerCase();
            if (placeNameLower.length < 4) continue;

            const idx = findTermInText(transcriptLower, placeNameLower);
            if (idx >= 0) {
              // VERB-DRIVEN ROLE DETECTION
              const { role, trigger_verb } = detectPlaceRole(transcriptLower, idx, placeNameLower);

              const mention: PlaceMention = {
                place_name: place.name,
                geo_place_id: place.id,
                lat: place.lat,
                lon: place.lon,
                role,
                trigger_verb,
                char_offset: idx,
                snippet: snippetAround(transcriptClean, idx, place.name.length),
              };

              place_mentions.push(mention);

              mentionedPlaces.push({
                id: place.id,
                name: place.name,
                lat: place.lat,
                lon: place.lon,
                char_offset: idx,
                role,
                trigger_verb,
                snippet: mention.snippet,
              });
            }
          }

          // Insert place mentions into span_place_mentions (upsert)
          if (mentionedPlaces.length > 0) {
            sources_used.push("geo_proximity");

            // Map to actual DB schema: (span_id, place_id, mention_text, role, verb_hint, confidence)
            // PK is (span_id, place_id, mention_text)
            const insertRows = mentionedPlaces.map((p) => ({
              span_id: span_id,
              place_id: p.id,
              mention_text: p.name,
              role: p.role,
              verb_hint: p.trigger_verb,
              confidence: p.role === "proximity" ? 0.5 : 0.8,
            }));

            // Upsert using PK columns (PR-9 hotfix)
            // PK: span_place_mentions_pkey (span_id, place_id, mention_text)
            const { error: upsertErr } = await db.from("span_place_mentions").upsert(insertRows, {
              onConflict: "span_id,place_id,mention_text",
            });
            if (upsertErr) {
              // FAIL CLOSED: upsert failure is fatal (schema/PK mismatch)
              return new Response(
                JSON.stringify({
                  ok: false,
                  error: "span_place_mentions_upsert_failed",
                  detail: upsertErr.message,
                  ms: Date.now() - t0,
                }),
                { status: 500, headers: { "Content-Type": "application/json" } },
              );
            }

            // Log enroute detections
            const enrouteCount = mentionedPlaces.filter((p) => p.role !== "proximity").length;
            if (enrouteCount > 0) {
              warnings.push(`enroute_detected:${enrouteCount}`);
            }

            // Find nearby projects (geo proximity candidates)
            // PR-11: Join projects table to filter by status and project_kind
            const { data: projectGeos, error: geoErr } = await db
              .from("project_geo")
              .select("project_id, lat, lon, projects!inner(status, project_kind)")
              .in("projects.status", VALID_PROJECT_STATUSES)
              .eq("projects.project_kind", VALID_PROJECT_KIND);

            if (!geoErr && projectGeos?.length) {
              const nearbyProjects = new Map<
                string,
                {
                  min_distance_km: number;
                  role_counts: Record<PlaceRole, number>;
                  place_names: Set<string>;
                }
              >();

              for (const place of mentionedPlaces) {
                for (const pg of projectGeos) {
                  if (!pg.project_id || pg.lat == null || pg.lon == null) continue;

                  const distance = haversineDistanceKm(
                    place.lat,
                    place.lon,
                    pg.lat,
                    pg.lon,
                  );

                  if (distance <= GEO_MAX_DISTANCE_KM) {
                    const existing = nearbyProjects.get(pg.project_id) || {
                      min_distance_km: Number.POSITIVE_INFINITY,
                      role_counts: emptyRoleCounts(),
                      place_names: new Set<string>(),
                    };
                    existing.min_distance_km = Math.min(existing.min_distance_km, distance);
                    existing.role_counts[place.role] = (existing.role_counts[place.role] || 0) + 1;
                    existing.place_names.add(place.name);
                    nearbyProjects.set(pg.project_id, existing);
                  }
                }
              }

              const sortedNearby = Array.from(nearbyProjects.entries())
                .sort((a, b) => a[1].min_distance_km - b[1].min_distance_km)
                .slice(0, GEO_MAX_CANDIDATES);

              for (const [pid, signal] of sortedNearby) {
                const placeCount = signal.place_names.size;
                const weakGeoScore = computeGeoWeakScore(
                  signal.min_distance_km,
                  signal.role_counts,
                  placeCount,
                );
                addCandidate(
                  pid,
                  "geo_proximity",
                  0,
                  Math.round(signal.min_distance_km * 10) / 10,
                  {
                    score: Math.round(weakGeoScore * 100) / 100,
                    dominant_role: dominantRoleFromCounts(signal.role_counts),
                    role_counts: signal.role_counts,
                    place_count: placeCount,
                  },
                );
              }

              if (sortedNearby.length > 0) {
                warnings.push(`geo_candidates_added:${sortedNearby.length}`);
                warnings.push("geo_ai_signal_enriched");
              }
            }
          }
        }
      } catch (_geoErr) {
        warnings.push("geo_lookup_skipped");
      }
    }

    // ========================================
    // CONTINUITY BUNDLE (Back-to-back calls within 48h)
    // Tiered linking: TIER_1 project mention, TIER_2 callback phrase, TIER_3 recency
    // Floater rule: if floater or gap > 4h, require TIER_1
    // ========================================
    if (contact_id && event_at_utc && transcript_text) {
      try {
        const eventMs = Date.parse(event_at_utc);
        if (!Number.isNaN(eventMs)) {
          const sinceIso = new Date(eventMs - CONTINUITY_LOOKBACK_HOURS * 60 * 60 * 1000).toISOString();
          const { data: priorRows } = await db
            .from("interactions")
            .select("interaction_id, project_id, event_at_utc")
            .eq("contact_id", contact_id)
            .lt("event_at_utc", event_at_utc)
            .gte("event_at_utc", sinceIso)
            .order("event_at_utc", { ascending: false })
            .limit(CONTINUITY_MAX_PRIOR_CALLS * 2);

          const projectIds = Array.from(
            new Set((priorRows || []).map((r) => r.project_id).filter(Boolean) as string[]),
          );
          const priorProjectNames = new Map<string, string>();
          if (projectIds.length) {
            const { data: pnameRows } = await db.from("projects").select("id, name").in("id", projectIds);
            for (const r of (pnameRows || [])) {
              if (r.id) priorProjectNames.set(r.id, r.name || r.id);
            }
          }

          const tierRank: Record<string, number> = { TIER_1: 0, TIER_2: 1, TIER_3: 2 };
          for (const row of (priorRows || [])) {
            if (!row.interaction_id || !row.event_at_utc) continue;
            const priorMs = Date.parse(row.event_at_utc);
            if (Number.isNaN(priorMs)) continue;
            const gapMinutes = Math.max(0, Math.round((eventMs - priorMs) / 60000));
            if (gapMinutes > CONTINUITY_LOOKBACK_HOURS * 60) continue;

            const isFloaterSensitive = floater_flag || gapMinutes > CONTINUITY_FLOATER_GAP_HOURS * 60;
            const hasProjectMention = projectMentionSpans.length > 0;
            const hasCallback = callbackSpans.length > 0;

            let tier: "TIER_1" | "TIER_2" | "TIER_3" = "TIER_3";
            let reason = "recency_only";
            if (hasCallback) {
              tier = "TIER_2";
              reason = "callback_phrase";
            }
            if (hasProjectMention) {
              tier = "TIER_1";
              reason = "project_mention";
            }

            // Floater rule: require Tier1
            if (isFloaterSensitive && tier !== "TIER_1") continue;

            const spans: string[] = [];
            if (tier === "TIER_1") spans.push(...projectMentionSpans.slice(0, 5));
            if (tier === "TIER_1" || tier === "TIER_2") spans.push(...callbackSpans.slice(0, 5));
            const trimmedSpans = spans.slice(0, 5).map((s) => s.slice(0, 80));

            continuity_links.push({
              prior_interaction_id: row.interaction_id,
              prior_project_id: row.project_id || null,
              prior_project_name: row.project_id ? priorProjectNames.get(row.project_id) || row.project_id : null,
              prior_event_at_utc: row.event_at_utc || null,
              gap_minutes: gapMinutes,
              tier,
              evidence: {
                reason,
                spans: trimmedSpans,
                callback_phrase_hits: callbackSpans,
              },
            });
          }

          continuity_links = continuity_links
            .sort((a, b) => {
              const tierDiff = tierRank[a.tier] - tierRank[b.tier];
              if (tierDiff !== 0) return tierDiff;
              return a.gap_minutes - b.gap_minutes;
            })
            .slice(0, CONTINUITY_MAX_PRIOR_CALLS);

          if (continuity_links.length > 0) {
            sources_used.push("continuity_bundle");
          }
        } else {
          warnings.push("continuity_no_event_time");
        }
      } catch (_contErr) {
        warnings.push("continuity_bundle_failed");
      }
    }

    // ========================================
    // ENRICH CANDIDATES WITH PROJECT DETAILS
    // ========================================
    const candidateIds = Array.from(candidatesById.keys());
    const projectDetailsById = new Map<string, {
      name: string;
      address: string | null;
      client_name: string | null;
      aliases: string[];
      status: string | null;
      phase: string | null;
    }>();

    if (candidateIds.length) {
      const { data: prows } = await db
        .from("projects")
        .select("id, name, address, client_name, aliases, status, phase")
        .in("id", candidateIds);

      if (prows) {
        for (const p of prows) {
          if (p.id) {
            projectDetailsById.set(p.id, {
              name: p.name || p.id,
              address: p.address || null,
              client_name: p.client_name || null,
              aliases: Array.isArray(p.aliases) ? p.aliases : [],
              status: p.status || null,
              phase: p.phase || null,
            });
          }
        }
      }

      try {
        const { data: enrichAliasRows, error: aliasErr } = await db
          .from("v_project_alias_lookup")
          .select("project_id, alias")
          .in("project_id", candidateIds);

        if (!aliasErr && enrichAliasRows) {
          for (const r of enrichAliasRows) {
            if (r.project_id && r.alias) {
              const details = projectDetailsById.get(r.project_id);
              if (details && !details.aliases.includes(r.alias)) {
                details.aliases.push(r.alias);
              }
            }
          }
        }
      } catch {
        // View doesn't exist
      }
    }

    // ========================================
    // BUILD CANDIDATES ARRAY
    // PHONETIC-ADJACENT-ONLY: classify match strength, flag weak-only candidates
    // ========================================
    const candidates: Candidate[] = [];

    for (const [pid, meta] of candidatesById) {
      const details = projectDetailsById.get(pid);
      if (!details) continue;

      // Classify each alias match as strong or weak
      const hasAliasEvidence = meta.alias_matches.length > 0;
      const hasStrongMatch = meta.alias_matches.some(
        (m) => classifyMatchStrength(m.term, m.match_type, details.name) === "strong",
      );
      const weakOnly = hasAliasEvidence && !hasStrongMatch && !meta.assigned;

      if (weakOnly) {
        warnings.push(`weak_alias_only:${details.name}`);
      }

      candidates.push({
        project_id: pid,
        project_name: details.name,
        address: details.address,
        client_name: details.client_name,
        aliases: details.aliases,
        status: details.status,
        phase: details.phase,
        evidence: {
          sources: meta.sources,
          affinity_weight: meta.affinity_weight,
          assigned: meta.assigned,
          alias_matches: meta.alias_matches,
          geo_distance_km: meta.geo_distance_km,
          geo_signal: meta.geo_signal,
          weak_only: weakOnly || undefined,
        },
      });
    }

    // Sort by evidence strength
    // PHONETIC-ADJACENT-ONLY: weak-only candidates sort below strong candidates
    candidates.sort((a, b) => {
      if (a.evidence.assigned !== b.evidence.assigned) return a.evidence.assigned ? -1 : 1;
      // Strong evidence beats weak evidence
      const aWeak = a.evidence.weak_only === true;
      const bWeak = b.evidence.weak_only === true;
      if (aWeak !== bWeak) return aWeak ? 1 : -1;
      if (b.evidence.alias_matches.length !== a.evidence.alias_matches.length) {
        return b.evidence.alias_matches.length - a.evidence.alias_matches.length;
      }
      if (b.evidence.affinity_weight !== a.evidence.affinity_weight) {
        return b.evidence.affinity_weight - a.evidence.affinity_weight;
      }
      const aGeoScore = a.evidence.geo_signal?.score || 0;
      const bGeoScore = b.evidence.geo_signal?.score || 0;
      if (bGeoScore !== aGeoScore) return bGeoScore - aGeoScore;
      const aGeoOnly = a.evidence.sources.length === 1 && a.evidence.sources[0] === "geo_proximity";
      const bGeoOnly = b.evidence.sources.length === 1 && b.evidence.sources[0] === "geo_proximity";
      if (aGeoOnly !== bGeoOnly) return aGeoOnly ? 1 : -1;
      if (a.evidence.geo_distance_km !== undefined && b.evidence.geo_distance_km !== undefined) {
        return a.evidence.geo_distance_km - b.evidence.geo_distance_km;
      }
      return 0;
    });

    if (candidates.length > MAX_CANDIDATES) {
      truncations.push(`candidates_capped_at_${MAX_CANDIDATES}`);
    }
    const finalCandidates = candidates.slice(0, MAX_CANDIDATES);

    // ========================================
    // SMART TRUNCATION OF TRANSCRIPT
    // ========================================
    const { text: finalTranscript, truncated } = smartTruncate(
      transcript_text,
      matchPositions,
      MAX_TRANSCRIPT_CHARS,
    );

    if (truncated) {
      truncations.push(`transcript_windowed_around_${matchPositions.length}_matches`);
    }

    // ========================================
    // v1.4.0: JOURNAL-DERIVED PROJECT STATE
    // Fetch active claims and open loops for each candidate project
    // This gives the ai-router knowledge of what's currently happening
    // on each candidate project (the "world model" context).
    // Non-fatal: if journal tables are empty or query fails, we skip.
    // ========================================
    const project_journal: ProjectJournalState[] = [];
    const candidateProjectIds = finalCandidates.map((c) => c.project_id).filter(Boolean);

    if (candidateProjectIds.length > 0) {
      try {
        // Null-contact calls are unanchored; skip journal context to prevent cross-contact leakage.
        if (!contact_id) {
          warnings.push("journal_source_unanchored_skipped");
        } else {
          // Pull a larger pool, then apply contact scoping before per-project caps.
          const { data: claimsData, error: claimsErr } = await db
            .from("journal_claims")
            .select("project_id, call_id, claim_type, claim_text, epistemic_status, created_at")
            .in("project_id", candidateProjectIds)
            .eq("active", true)
            .order("created_at", { ascending: false })
            .limit(candidateProjectIds.length * 25);

          const { data: loopsData, error: loopsErr } = await db
            .from("journal_open_loops")
            .select("project_id, call_id, loop_type, description, status, created_at")
            .in("project_id", candidateProjectIds)
            .eq("status", "open")
            .order("created_at", { ascending: false })
            .limit(candidateProjectIds.length * 12);

          if (!claimsErr && !loopsErr) {
            const callIds = Array.from(
              new Set([
                ...(claimsData || []).map((c) => c.call_id).filter(Boolean),
                ...(loopsData || []).map((l) => l.call_id).filter(Boolean),
              ] as string[]),
            );

            const sourceCalls = new Map<string, { contact_id: string | null; contact_phone: string | null }>();
            if (callIds.length > 0) {
              const { data: sourceCallRows } = await db
                .from("interactions")
                .select("interaction_id, contact_id, contact_phone")
                .in("interaction_id", callIds);

              for (const row of (sourceCallRows || [])) {
                sourceCalls.set(row.interaction_id, {
                  contact_id: row.contact_id,
                  contact_phone: row.contact_phone,
                });
              }
            }

            let scopedClaimsAdded = 0;
            let scopedLoopsAdded = 0;

            // Group claims by project
            const claimsByProject = new Map<string, JournalClaim[]>();
            for (const c of (claimsData || [])) {
              if (!c.project_id) continue;
              const source = c.call_id ? sourceCalls.get(c.call_id) : undefined;
              if (!source) continue;
              if (!matchesJournalSourceContact(contact_id, contact_phone, source.contact_id, source.contact_phone)) {
                continue;
              }
              if (!claimsByProject.has(c.project_id)) claimsByProject.set(c.project_id, []);
              const arr = claimsByProject.get(c.project_id)!;
              if (arr.length < 5) { // Cap at 5 per project
                arr.push({
                  claim_type: c.claim_type,
                  claim_text: (c.claim_text || "").slice(0, 200),
                  epistemic_status: c.epistemic_status,
                  created_at: c.created_at,
                });
                scopedClaimsAdded += 1;
              }
            }

            // Group open loops by project
            const loopsByProject = new Map<string, JournalOpenLoop[]>();
            for (const l of (loopsData || [])) {
              if (!l.project_id) continue;
              const source = l.call_id ? sourceCalls.get(l.call_id) : undefined;
              if (!source) continue;
              if (!matchesJournalSourceContact(contact_id, contact_phone, source.contact_id, source.contact_phone)) {
                continue;
              }
              if (!loopsByProject.has(l.project_id)) loopsByProject.set(l.project_id, []);
              const arr = loopsByProject.get(l.project_id)!;
              if (arr.length < 3) { // Cap at 3 per project
                arr.push({
                  loop_type: l.loop_type,
                  description: (l.description || "").slice(0, 200),
                  status: l.status,
                });
                scopedLoopsAdded += 1;
              }
            }

            // Build per-project state
            let journalSourceAdded = false;
            for (const pid of candidateProjectIds) {
              const claims = claimsByProject.get(pid) || [];
              const loops = loopsByProject.get(pid) || [];

              if (claims.length > 0 || loops.length > 0) {
                project_journal.push({
                  project_id: pid,
                  active_claims_count: claims.length, // Note: this is capped at 5, actual count may be higher
                  recent_claims: claims,
                  open_loops: loops,
                  last_journal_activity: claims.length > 0 ? claims[0].created_at : null,
                });
                if (!journalSourceAdded) {
                  sources_used.push("journal_claims");
                  journalSourceAdded = true;
                }
              }
            }

            if (scopedClaimsAdded === 0 && scopedLoopsAdded === 0) {
              warnings.push("journal_contact_scope_no_matches");
            }
          }
        }
      } catch (_journalErr) {
        // Non-fatal: journal tables may not be populated yet
        warnings.push("journal_state_skipped");
      }
    }

    // ========================================
    // BUILD CONTEXT PACKAGE
    // ========================================
    const context_package: ContextPackage = {
      meta: {
        assembly_version: ASSEMBLY_VERSION,
        selection_rules_version: SELECTION_RULES_VERSION,
        span_id,
        interaction_id: interaction_id!,
        assembled_at_utc: new Date().toISOString(),
        truncations,
        warnings,
        sources_used,
      },
      span: {
        start_ms,
        end_ms,
        transcript_text: finalTranscript,
        words,
      },
      contact: {
        contact_id,
        contact_name,
        phone_e164_last4,
        floater_flag,
        fanout_class,
        effective_fanout,
        recent_projects,
      },
      candidates: finalCandidates,
      place_mentions,
      project_journal,
      email_context,
      email_lookup_meta,
      continuity_links,
    };

    return new Response(
      JSON.stringify({
        ok: true,
        context_package,
        ms: Date.now() - t0,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (e: any) {
    console.error("context-assembly error:", e.message);
    return new Response(
      JSON.stringify({
        ok: false,
        error: e.message,
        ms: Date.now() - t0,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
