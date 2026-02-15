/**
 * Semantic Claim Cross-Reference Scoring Module
 * ==============================================
 *
 * PURPOSE: Pre-LLM scoring step that computes semantic similarity between
 * transcript content and journal claims for each candidate project.
 * Designed to run INSIDE context-assembly (Deno/TypeScript Edge Function).
 *
 * THE PROBLEM: When a floater contact (works on 5+ projects) calls, the
 * pipeline has no contact-identity signal. It relies on transcript content
 * matching to find the right project. The LLM gets distracted by surface-level
 * word matches (e.g., "mystery white" marble -> "White Residence" project).
 *
 * THE SOLUTION: Compute term-overlap scores weighted by inverse document
 * frequency (IDF) across candidate projects' journal claims. Specific terms
 * that appear in few projects' claims score higher than generic trade terms.
 *
 * ALGORITHM OVERVIEW:
 * 1. Extract meaningful terms from transcript (nouns, amounts, materials, trade terms)
 * 2. For each candidate, extract terms from their journal claims
 * 3. Compute IDF weights: terms appearing in fewer projects' claims are more valuable
 * 4. Score each candidate by weighted overlap of transcript terms in their claims
 * 5. Normalize to 0.0-1.0 range
 *
 * INTEGRATION POINT: This runs after journal claims are fetched (line ~2175 in
 * context-assembly/index.ts) and before the context_package is built (line ~2310).
 * The score goes into candidate.evidence.claim_crossref_score and the ai-router
 * prompt includes it on the Evidence line (alongside source_strength).
 *
 * NO DEPENDENCIES: Works without pgvector. Pure keyword/topic overlap with IDF weighting.
 *
 * @version 1.0.0
 * @author DATA-1
 * @date 2026-02-14
 */

// ============================================================
// TYPES
// ============================================================

/** A single claim that matched transcript content */
interface MatchingClaim {
  claim_text: string;
  claim_type: string;
  overlap_terms: string[];
}

/** Cross-reference result for one candidate project */
export interface CrossrefResult {
  project_id: string;
  claim_crossref_score: number; // 0.0 to 1.0
  matching_topics: string[]; // Transcript terms that matched this project's claims
  matching_claims: MatchingClaim[];
}

/** Input candidate shape (matches context-assembly's candidate structure) */
interface CandidateInput {
  project_id: string;
  project_name: string;
}

/** Input journal claim shape (matches context-assembly's journal_claims query) */
interface JournalClaimInput {
  project_id: string;
  claim_text: string;
  claim_type: string;
  attribution_decision?: string;
}

// ============================================================
// STOPWORDS
// ============================================================

/**
 * Stopwords list: common English words that carry no semantic signal for
 * construction-domain matching. We keep it tight -- better to let a marginal
 * word through than to filter out a meaningful one.
 *
 * DESIGN CHOICE: We split stopwords into two tiers:
 * - HARD stopwords: always filtered (the, is, and, etc.)
 * - We do NOT filter construction/trade terms even if they look generic
 *   ("tub", "tile", "paint") because those carry signal in this domain.
 */
const STOPWORDS = new Set([
  // Determiners / pronouns
  "the",
  "a",
  "an",
  "this",
  "that",
  "these",
  "those",
  "it",
  "its",
  "he",
  "she",
  "they",
  "them",
  "his",
  "her",
  "we",
  "our",
  "you",
  "your",
  "i",
  "me",
  "my",
  "mine",
  "who",
  "what",
  "which",
  "whom",
  // Prepositions / conjunctions
  "in",
  "on",
  "at",
  "to",
  "for",
  "of",
  "with",
  "from",
  "by",
  "as",
  "into",
  "about",
  "up",
  "out",
  "over",
  "after",
  "before",
  "between",
  "and",
  "or",
  "but",
  "so",
  "if",
  "then",
  "than",
  "because",
  "when",
  "where",
  "how",
  "while",
  "until",
  "although",
  "though",
  // Common verbs (non-construction)
  "is",
  "are",
  "was",
  "were",
  "be",
  "been",
  "being",
  "have",
  "has",
  "had",
  "do",
  "does",
  "did",
  "will",
  "would",
  "could",
  "should",
  "shall",
  "may",
  "might",
  "can",
  "must",
  "get",
  "got",
  "getting",
  "let",
  "make",
  "made",
  "take",
  "took",
  "give",
  "gave",
  "go",
  "going",
  "went",
  "gone",
  "come",
  "came",
  "say",
  "said",
  "says",
  "tell",
  "told",
  "know",
  "knew",
  "think",
  "thought",
  "see",
  "saw",
  "look",
  "want",
  "wanted",
  "need",
  "needed",
  "just",
  "like",
  "well",
  "here",
  "there",
  "now",
  "also",
  "still",
  // Filler / conversational
  "yeah",
  "yes",
  "no",
  "not",
  "okay",
  "ok",
  "right",
  "um",
  "uh",
  "hmm",
  "gonna",
  "gotta",
  "wanna",
  "kinda",
  "sorta",
  "actually",
  "basically",
  "really",
  "very",
  "much",
  "some",
  "any",
  "all",
  "each",
  "every",
  "other",
  "another",
  "more",
  "most",
  "enough",
  "too",
  "already",
  "thing",
  "things",
  "stuff",
  "something",
  "anything",
  "nothing",
  "somebody",
  "someone",
  "everybody",
  "everyone",
  // Time words (non-specific)
  "today",
  "tomorrow",
  "yesterday",
  "time",
  "day",
  "week",
  "month",
  // Numbers that are too generic (we keep dollar amounts via special extraction)
  "one",
  "two",
  "three",
  "four",
  "five",
  "six",
  "seven",
  "eight",
  "nine",
  "ten",
  // Misc
  "way",
  "lot",
  "back",
  "even",
  "through",
  "down",
  "only",
  "been",
  "same",
  "own",
  "part",
  "first",
  "last",
  "next",
  "new",
  "old",
  "big",
  "little",
  "long",
  "good",
  "bad",
  "great",
  "sure",
  "probably",
]);

// ============================================================
// CONSTRUCTION DOMAIN TERMS (HIGH SIGNAL)
// ============================================================

/**
 * Construction/trade terms that carry EXTRA weight in matching.
 * These are domain-specific and highly diagnostic -- if a transcript
 * mentions "quartz" and a journal claim also mentions "quartz",
 * that is a strong semantic link.
 *
 * We boost these by 1.5x on top of their IDF weight.
 */
const CONSTRUCTION_TERMS = new Set([
  // Materials - Stone/Countertop
  "marble",
  "granite",
  "quartz",
  "quartzite",
  "soapstone",
  "travertine",
  "limestone",
  "onyx",
  "porcelain",
  "ceramic",
  "slate",
  "sandstone",
  "countertop",
  "countertops",
  "backsplash",
  "slab",
  "slabs",
  // Materials - Wood
  "hardwood",
  "softwood",
  "plywood",
  "shiplap",
  "wainscoting",
  "trim",
  "molding",
  "moulding",
  "baseboard",
  "crown",
  "casing",
  "mantel",
  "mantle",
  "stair",
  "stairs",
  "staircase",
  "railing",
  "banister",
  "newel",
  "baluster",
  // Materials - Flooring
  "tile",
  "tiles",
  "tiling",
  "grout",
  "mortar",
  "thinset",
  "flooring",
  "hardwoods",
  "laminate",
  "vinyl",
  "carpet",
  "rug",
  "subfloor",
  "underlayment",
  // Plumbing
  "tub",
  "bathtub",
  "shower",
  "faucet",
  "toilet",
  "sink",
  "vanity",
  "plumbing",
  "pipe",
  "pipes",
  "drain",
  "drainage",
  "sewer",
  "tankless",
  "valve",
  "fixture",
  "fixtures",
  // Electrical
  "electrical",
  "wiring",
  "panel",
  "breaker",
  "outlet",
  "switch",
  "lighting",
  "light",
  "lights",
  "chandelier",
  "sconce",
  "recessed",
  "dimmer",
  "generator",
  "transformer",
  // HVAC
  "hvac",
  "furnace",
  "ductwork",
  "ducts",
  "thermostat",
  "compressor",
  "condenser",
  // Structural
  "foundation",
  "footing",
  "footer",
  "beam",
  "joist",
  "rafter",
  "truss",
  "header",
  "column",
  "post",
  "pier",
  "slab",
  "framing",
  "studs",
  "sheathing",
  // Exterior
  "siding",
  "roofing",
  "shingle",
  "shingles",
  "gutter",
  "gutters",
  "soffit",
  "fascia",
  "flashing",
  "dormer",
  "skylight",
  "window",
  "windows",
  "door",
  "doors",
  "garage",
  // Finishes
  "paint",
  "primer",
  "stain",
  "varnish",
  "lacquer",
  "polyurethane",
  "drywall",
  "plaster",
  "texture",
  "wallpaper",
  "caulk",
  "caulking",
  // Appliances / Fixtures
  "appliance",
  "appliances",
  "range",
  "oven",
  "refrigerator",
  "dishwasher",
  "microwave",
  "hood",
  "vent",
  // Trade roles
  "plumber",
  "electrician",
  "painter",
  "framer",
  "drywaller",
  "roofer",
  "mason",
  "tiler",
  "carpenter",
  "cabinetmaker",
  "contractor",
  "subcontractor",
  "inspector",
  // Construction phases
  "demolition",
  "demo",
  "excavation",
  "inspection",
  "walkthrough",
  "closeout",
  "warranty",
  "permit",
  // Cabinetry
  "cabinet",
  "cabinets",
  "cabinetry",
  "drawer",
  "drawers",
  "shelf",
  "shelves",
  "shelving",
  "pantry",
  "closet",
]);

// ============================================================
// TERM EXTRACTION
// ============================================================

/**
 * Extract dollar amounts from text.
 * Captures patterns like: $3000, $3,000, $6,000, $150,000, $1.2M
 * Dollar amounts are extremely specific and diagnostic.
 *
 * Returns normalized strings like "$3000", "$6000", "$150000"
 */
function extractDollarAmounts(text: string): string[] {
  const amounts: string[] = [];
  // Match $X,XXX or $X.XM/K patterns
  const dollarRegex = /\$[\d,]+(?:\.\d+)?(?:\s*(?:k|m|million|thousand|hundred))?/gi;
  const matches = text.match(dollarRegex);
  if (matches) {
    for (const m of matches) {
      // Normalize: remove commas, collapse to number
      const normalized = m.replace(/,/g, "").toLowerCase().trim();
      amounts.push(normalized);
    }
  }

  // Also catch spoken amounts: "three thousand dollars", "6000 dollars", "3000 apiece"
  const spokenRegex = /(\d[\d,]*)\s*(?:dollars?|bucks?|apiece|each|per)/gi;
  let match: RegExpExecArray | null;
  while ((match = spokenRegex.exec(text)) !== null) {
    const num = match[1].replace(/,/g, "");
    amounts.push("$" + num);
  }

  return [...new Set(amounts)];
}

/**
 * Extract multi-word compound terms that are more specific than individual words.
 * E.g., "mystery white", "wrong size", "two slabs", "send it back"
 *
 * Returns lowercased compound terms.
 */
function extractCompoundTerms(text: string): string[] {
  const compounds: string[] = [];
  const lower = text.toLowerCase();

  // Material + color/type compounds (e.g., "mystery white", "calacatta gold")
  const materialColorRegex =
    /\b([a-z]+)\s+(white|black|gray|grey|gold|blue|green|red|brown|beige|cream|silver|bronze)\b/g;
  let m: RegExpExecArray | null;
  while ((m = materialColorRegex.exec(lower)) !== null) {
    if (!STOPWORDS.has(m[1])) {
      compounds.push(m[0]);
    }
  }

  // "wrong size/wrong X" patterns (problem indicators)
  const problemRegex = /\b(wrong|broken|damaged|cracked|chipped|missing|defective|leaking|leaky)\s+(\w+)/g;
  while ((m = problemRegex.exec(lower)) !== null) {
    compounds.push(m[0]);
  }

  // "send back / send it back / return / exchange" patterns
  const returnRegex = /\b(send\s+(?:it\s+)?back|return(?:ed|ing)?|exchange(?:d|ing)?|replace(?:d|ment)?)\b/g;
  while ((m = returnRegex.exec(lower)) !== null) {
    compounds.push(m[0].replace(/\s+/g, " ").trim());
  }

  // Quantity + material: "two slabs", "three tubs", "four panels"
  const qtyRegex =
    /\b(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+(slab|tub|panel|sheet|piece|tile|board|cabinet|door|window|fixture)s?\b/g;
  while ((m = qtyRegex.exec(lower)) !== null) {
    compounds.push(m[0]);
  }

  return [...new Set(compounds)];
}

/**
 * Extract proper nouns (capitalized words that are not sentence-starters).
 * These are often names -- "Skelton", "Permar", "Randy" -- which are
 * extremely diagnostic for project matching.
 */
function extractProperNouns(text: string): string[] {
  const proper: string[] = [];
  // Match capitalized words that are NOT at sentence start (preceded by lowercase/punct + space)
  // Also grab words in ALL CAPS if they look like names
  const words = text.split(/\s+/);
  for (let i = 0; i < words.length; i++) {
    const word = words[i].replace(/[^a-zA-Z']/g, "");
    if (!word || word.length < 3) continue;
    // Skip if it is a known stopword when lowered
    if (STOPWORDS.has(word.toLowerCase())) continue;
    // Proper noun: starts with capital, rest lowercase, not first word after period/newline
    if (/^[A-Z][a-z]{2,}$/.test(word)) {
      // Check it is not a sentence starter -- if previous token ends with . or is empty, skip
      if (i > 0) {
        const prev = words[i - 1];
        if (!prev.endsWith(".") && !prev.endsWith("?") && !prev.endsWith("!")) {
          proper.push(word.toLowerCase());
        }
      }
    }
  }
  return [...new Set(proper)];
}

/**
 * Primary tokenizer: extract meaningful single terms from text.
 * Filters stopwords, keeps construction terms, keeps proper nouns,
 * keeps terms >= 4 chars (or >= 3 if not purely numeric).
 *
 * Returns lowercased tokens.
 */
function tokenize(text: string): string[] {
  const tokens = (text || "")
    .toLowerCase()
    .replace(/[^a-z0-9$]+/g, " ")
    .split(/\s+/)
    .filter((t) => t.length >= 3)
    .filter((t) => !STOPWORDS.has(t))
    // Filter out bare single/double digit numbers (too generic)
    .filter((t) => !(t.length <= 2 && /^\d+$/.test(t)));

  return [...new Set(tokens)];
}

/**
 * Full transcript term extraction: combines single tokens, compound terms,
 * dollar amounts, and proper nouns into a unified term set.
 *
 * Each term is tagged with a "specificity class" used for weighting:
 * - "dollar": dollar amounts ($3000) -- highest intrinsic specificity
 * - "compound": multi-word phrases (mystery white) -- high specificity
 * - "proper": proper nouns (Skelton) -- high specificity
 * - "construction": domain-specific single terms (marble, slab) -- medium specificity
 * - "generic": other meaningful terms -- base specificity
 */
interface TaggedTerm {
  term: string;
  specificity: "dollar" | "compound" | "proper" | "construction" | "generic";
}

function extractTranscriptTerms(text: string): TaggedTerm[] {
  const terms: Map<string, TaggedTerm> = new Map();

  // 1. Dollar amounts (highest specificity)
  for (const amt of extractDollarAmounts(text)) {
    const key = amt.toLowerCase();
    terms.set(key, { term: key, specificity: "dollar" });
  }

  // 2. Compound terms (high specificity)
  for (const comp of extractCompoundTerms(text)) {
    const key = comp.toLowerCase();
    if (!terms.has(key)) {
      terms.set(key, { term: key, specificity: "compound" });
    }
  }

  // 3. Proper nouns (high specificity)
  for (const pn of extractProperNouns(text)) {
    const key = pn.toLowerCase();
    if (!terms.has(key)) {
      terms.set(key, { term: key, specificity: "proper" });
    }
  }

  // 4. Single tokens (construction or generic)
  for (const tok of tokenize(text)) {
    if (!terms.has(tok)) {
      const spec = CONSTRUCTION_TERMS.has(tok) ? "construction" : "generic";
      terms.set(tok, { term: tok, specificity: spec });
    }
  }

  return Array.from(terms.values());
}

// ============================================================
// IDF COMPUTATION
// ============================================================

/**
 * Compute inverse document frequency for each transcript term across
 * all candidate projects' journal claims.
 *
 * IDF = log(N / df) where:
 * - N = total number of candidate projects with at least 1 claim
 * - df = number of projects whose claims contain this term
 *
 * Terms that appear in ALL projects' claims get IDF ~0 (not useful).
 * Terms that appear in only 1 project's claims get max IDF (very useful).
 *
 * We add 1 to both numerator and denominator (Laplace smoothing) to avoid
 * division by zero and to dampen extreme values.
 */
function computeIdf(
  transcriptTerms: TaggedTerm[],
  claimsByProject: Map<string, string>, // project_id -> concatenated claim text (lowercased)
): Map<string, number> {
  const idf = new Map<string, number>();
  const N = claimsByProject.size;
  if (N === 0) return idf;

  // Pre-tokenize each project's claim text for faster single-term lookups
  const tokenizedClaims = new Map<string, Set<string>>();
  for (const [pid, claimText] of claimsByProject) {
    tokenizedClaims.set(pid, new Set(tokenize(claimText)));
  }

  // For each transcript term, count how many projects' claims contain it
  for (const { term } of transcriptTerms) {
    let df = 0;
    for (const [pid, claimText] of claimsByProject) {
      if (term.includes(" ")) {
        // Compound term: substring match in raw text
        if (claimText.includes(term)) df++;
      } else {
        // Single term: check tokenized set for exact or stem-like match
        const tokens = tokenizedClaims.get(pid)!;
        if (tokens.has(term)) {
          df++;
        } else if (term.length >= 5) {
          // Stem match for longer terms
          for (const t of tokens) {
            if (t.length >= 5 && (t.startsWith(term) || term.startsWith(t))) {
              df++;
              break;
            }
          }
        }
      }
    }
    // IDF with base weight floor.
    // Pure IDF = log((N+1)/(df+1)) which is 0 when df=N (term in all projects).
    // We add a BASE_MATCH_WEIGHT so that matching still accumulates some score
    // even when the term has no discriminative power across projects.
    // This handles the single-candidate case (N=1, df=1 -> IDF=0) and the
    // all-projects case (df=N -> IDF=0) gracefully.
    const BASE_MATCH_WEIGHT = 0.15;
    const rawIdf = Math.log((N + 1) / (df + 1));
    idf.set(term, rawIdf + (df > 0 ? BASE_MATCH_WEIGHT : 0));
  }

  return idf;
}

// ============================================================
// SPECIFICITY MULTIPLIERS
// ============================================================

/**
 * Intrinsic specificity multiplier by term class.
 * These multiply WITH the IDF weight.
 *
 * Rationale:
 * - Dollar amounts are almost always unique to a conversation topic
 * - Compound terms (material + color) are highly diagnostic
 * - Proper nouns strongly indicate a person/project
 * - Construction terms are domain-relevant but can be generic
 * - Generic terms provide weak but cumulative signal
 */
const SPECIFICITY_MULTIPLIER: Record<string, number> = {
  dollar: 3.0,
  compound: 2.5,
  proper: 2.0,
  construction: 1.5,
  generic: 1.0,
};

// ============================================================
// MAIN SCORING FUNCTION
// ============================================================

/**
 * Compute claim cross-reference scores for each candidate project.
 *
 * For each candidate, we:
 * 1. Collect all journal claims for that project
 * 2. Tokenize the claim text into a searchable string
 * 3. For each transcript term, check if it appears in the claims
 * 4. Weight the match by: IDF * specificity_multiplier
 * 5. Sum weights, normalize to 0.0-1.0
 *
 * The normalization is against the THEORETICAL MAXIMUM for that transcript:
 * if every transcript term matched in a single project's claims, the score
 * would be 1.0. This makes scores comparable across different transcripts.
 *
 * @param transcript_text - The raw transcript segment text
 * @param candidates - Array of candidate projects (project_id + project_name)
 * @param journal_claims - Array of journal claims with project_id, claim_text, claim_type
 * @returns CrossrefResult[] sorted by claim_crossref_score descending
 */
export function computeClaimCrossref(
  transcript_text: string,
  candidates: CandidateInput[],
  journal_claims: JournalClaimInput[],
): CrossrefResult[] {
  // Edge case: no transcript or no candidates
  if (!transcript_text || transcript_text.trim().length === 0 || candidates.length === 0) {
    return candidates.map((c) => ({
      project_id: c.project_id,
      claim_crossref_score: 0,
      matching_topics: [],
      matching_claims: [],
    }));
  }

  // ---- STEP 1: Extract terms from transcript ----
  const transcriptTerms = extractTranscriptTerms(transcript_text);

  if (transcriptTerms.length === 0) {
    return candidates.map((c) => ({
      project_id: c.project_id,
      claim_crossref_score: 0,
      matching_topics: [],
      matching_claims: [],
    }));
  }

  // ---- STEP 2: Group journal claims by project ----
  // Build two structures:
  // a) claimTextByProject: concatenated lowercase text for IDF/matching
  // b) claimListByProject: original claims for result reporting
  const claimTextByProject = new Map<string, string>();
  const claimListByProject = new Map<string, JournalClaimInput[]>();

  const candidateIds = new Set(candidates.map((c) => c.project_id));

  for (const claim of journal_claims) {
    if (!candidateIds.has(claim.project_id)) continue;
    const text = (claim.claim_text || "").toLowerCase();
    if (!text) continue;

    // Concatenate text for IDF
    const existing = claimTextByProject.get(claim.project_id) || "";
    claimTextByProject.set(claim.project_id, existing + " " + text);

    // Store original claim
    if (!claimListByProject.has(claim.project_id)) {
      claimListByProject.set(claim.project_id, []);
    }
    claimListByProject.get(claim.project_id)!.push(claim);
  }

  // ---- STEP 3: Compute IDF weights ----
  const idfWeights = computeIdf(transcriptTerms, claimTextByProject);

  // ---- STEP 4: Compute theoretical maximum weight ----
  // This is the sum of all transcript term weights if they ALL matched.
  // Used for normalization.
  let maxPossibleWeight = 0;
  for (const { term, specificity } of transcriptTerms) {
    const idf = idfWeights.get(term) ?? Math.log(candidateIds.size + 1); // default: max IDF for unseen terms
    const mult = SPECIFICITY_MULTIPLIER[specificity] ?? 1.0;
    maxPossibleWeight += idf * mult;
  }

  if (maxPossibleWeight === 0) maxPossibleWeight = 1; // prevent division by zero

  // ---- STEP 5: Score each candidate ----
  const results: CrossrefResult[] = [];

  for (const candidate of candidates) {
    const claimText = claimTextByProject.get(candidate.project_id);
    const claimList = claimListByProject.get(candidate.project_id) || [];

    // No claims for this project = score 0
    if (!claimText || claimText.trim().length === 0) {
      results.push({
        project_id: candidate.project_id,
        claim_crossref_score: 0,
        matching_topics: [],
        matching_claims: [],
      });
      continue;
    }

    // Tokenize claim text for single-term matching
    const claimTokens = new Set(tokenize(claimText));
    const claimLower = claimText.toLowerCase();

    let weightedScore = 0;
    const matchingTopics: string[] = [];

    // Track which claims matched which terms (for the matching_claims output)
    const claimMatchMap = new Map<number, string[]>(); // claim index -> matching terms

    for (const { term, specificity } of transcriptTerms) {
      const idf = idfWeights.get(term) ?? 0;
      const mult = SPECIFICITY_MULTIPLIER[specificity] ?? 1.0;

      let matched = false;

      if (term.includes(" ")) {
        // Compound term: substring match in concatenated text
        if (claimLower.includes(term)) {
          matched = true;
        }
      } else {
        // Single term: check tokenized set for exact or stem-like match
        if (claimTokens.has(term)) {
          matched = true;
        } else {
          // Partial stem match: if transcript term is prefix of claim token or vice versa
          // Only for terms >= 5 chars to avoid false positives
          if (term.length >= 5) {
            for (const ct of claimTokens) {
              if (ct.length >= 5 && (ct.startsWith(term) || term.startsWith(ct))) {
                matched = true;
                break;
              }
            }
          }
        }
      }

      if (matched) {
        weightedScore += idf * mult;
        matchingTopics.push(term);

        // Find which specific claims contain this term
        for (let ci = 0; ci < claimList.length; ci++) {
          const ct = (claimList[ci].claim_text || "").toLowerCase();
          const ctTokens = tokenize(ct);
          const inClaim = term.includes(" ") ? ct.includes(term) : ctTokens.includes(term) || ctTokens.some(
            (t) => t.length >= 5 && term.length >= 5 && (t.startsWith(term) || term.startsWith(t)),
          );
          if (inClaim) {
            if (!claimMatchMap.has(ci)) claimMatchMap.set(ci, []);
            claimMatchMap.get(ci)!.push(term);
          }
        }
      }
    }

    // Normalize score to 0.0-1.0
    const normalizedScore = Math.min(1.0, weightedScore / maxPossibleWeight);

    // Build matching_claims from the map (only claims with matches, sorted by match count)
    const matchingClaims: MatchingClaim[] = [];
    const sortedClaimIndices = Array.from(claimMatchMap.entries())
      .sort((a, b) => b[1].length - a[1].length); // Most matching terms first

    for (const [ci, terms] of sortedClaimIndices) {
      const claim = claimList[ci];
      matchingClaims.push({
        claim_text: claim.claim_text,
        claim_type: claim.claim_type,
        overlap_terms: terms,
      });
    }

    results.push({
      project_id: candidate.project_id,
      claim_crossref_score: Math.round(normalizedScore * 1000) / 1000, // 3 decimal places
      matching_topics: [...new Set(matchingTopics)],
      matching_claims: matchingClaims,
    });
  }

  // ---- STEP 6: Sort by score descending ----
  results.sort((a, b) => b.claim_crossref_score - a.claim_crossref_score);

  return results;
}

// ============================================================
// INTEGRATION HELPER
// ============================================================

/**
 * Helper to merge crossref scores into candidate evidence objects.
 * Call this after computeClaimCrossref() to inject scores.
 *
 * Usage in context-assembly/index.ts (after project_journal is built, ~line 2305):
 *
 *   import { computeClaimCrossref, mergeScoresIntoCandidates } from "./claim_crossref.ts";
 *
 *   // Build flat claim list from project_journal
 *   const allClaims = project_journal.flatMap(pj =>
 *     pj.recent_claims.map(c => ({
 *       project_id: pj.project_id,
 *       claim_text: c.claim_text,
 *       claim_type: c.claim_type,
 *     }))
 *   );
 *   const crossrefResults = computeClaimCrossref(finalTranscript, finalCandidates, allClaims);
 *   mergeScoresIntoCandidates(finalCandidates, crossrefResults);
 *
 * This sets candidate.evidence.claim_crossref_score on each candidate.
 */
export function mergeScoresIntoCandidates(
  candidates: Array<{
    project_id: string;
    evidence: { claim_crossref_score?: number; [key: string]: unknown };
  }>,
  crossrefResults: CrossrefResult[],
): void {
  const scoreMap = new Map(crossrefResults.map((r) => [r.project_id, r.claim_crossref_score]));
  for (const candidate of candidates) {
    candidate.evidence.claim_crossref_score = scoreMap.get(candidate.project_id) ?? 0;
  }
}

// ============================================================
// AI-ROUTER PROMPT INTEGRATION NOTES
// ============================================================

/**
 * PROMPT CHANGE for ai-router/index.ts:
 *
 * In buildUserPrompt(), the Evidence line currently reads (line ~628):
 *
 *   - Evidence: assigned=${c.evidence.assigned}, affinity=${...}, source_strength=${...}, sources=[${...}]
 *
 * Add crossref_score after source_strength:
 *
 *   - Evidence: assigned=${c.evidence.assigned}, affinity=${c.evidence.affinity_weight.toFixed(2)}, source_strength=${
 *       (c.evidence.source_strength ?? 0).toFixed(2)
 *     }, crossref=${
 *       (c.evidence.claim_crossref_score ?? 0).toFixed(2)
 *     }, sources=[${
 *       c.evidence.sources.join(",")
 *     }]
 *
 * Also add to the system prompt explanation (before the candidate list):
 *
 *   "crossref: Semantic overlap between transcript content and this project's
 *    journal claims (0.0=no overlap, 1.0=perfect overlap). Higher crossref
 *    means the transcript topics match what is currently happening on this project."
 *
 * And update ContextPackage type in ai-router to include:
 *   claim_crossref_score?: number;
 * in the evidence object.
 */

// ============================================================
// CONTEXT-ASSEMBLY SORT INTEGRATION NOTES
// ============================================================

/**
 * SORT CHANGE for context-assembly/index.ts:
 *
 * Current sort order (v2.1.0, ~line 2100):
 *   assigned > weak_only > alias_matches > source_strength > affinity > geo
 *
 * Proposed new sort order (v2.2.0):
 *   assigned > weak_only > alias_matches > source_strength > claim_crossref > affinity > geo
 *
 * claim_crossref_score slots in between source_strength and affinity_weight
 * because it is transcript-grounded evidence (like source_strength) but derived
 * from journal history rather than direct alias/keyword matching.
 *
 * Candidates with crossref >= 0.3 AND source_strength < 0.2 should get a boost:
 * this is the exact case where journal cross-referencing adds the most value
 * (transcript evidence is weak but journal context is strong).
 */

// ============================================================
// TEST CASES
// ============================================================

/**
 * Test suite using the Skelton/White/Moss real-world example.
 *
 * Transcript context:
 * A floater (internal staff) calls about marble selection and a wrong-size tub.
 * The transcript mentions "mystery white", "$3000 apiece", "two slabs",
 * "tub was the wrong size", "send it back and get a new one".
 *
 * Expected behavior:
 * - Skelton Residence should score HIGHEST because their journal mentions
 *   marble selection ("picked out some marble") and tub issues
 * - White Residence should score LOW despite name similarity because their
 *   journal is about drain hookup (different tub context)
 * - Moss Residence should score LOW because journal is vague
 *   ("check for any toilets or tubs" -- no specifics)
 */

function runTests(): void {
  console.log("=== Claim Crossref Test Suite ===\n");

  // ---- TEST 1: Skelton/White/Moss Example ----
  const transcript = `does this customer the skeletons do they have a budget for
this countertop stone because we got the mystery white that she selected
and it's gonna be pretty expensive we're probably gonna have to buy two slabs
and they're about $3000 apiece so that's six thousand dollars worth of
material just for the stone and then we found out the tub was the wrong size
so we're gonna have to send it back and get a new one and that's gonna
cost us time and probably another $800 for restocking`;

  const candidates = [
    { project_id: "proj_skelton", project_name: "Skelton Residence" },
    { project_id: "proj_white", project_name: "White Residence" },
    { project_id: "proj_moss", project_name: "Moss Residence" },
  ];

  const journal_claims: JournalClaimInput[] = [
    // Skelton claims -- matches marble selection + tub topic
    {
      project_id: "proj_skelton",
      claim_text:
        "They picked out some marble -- mystery white from Arizona Tile. Customer is excited about the selection.",
      claim_type: "material_selection",
    },
    {
      project_id: "proj_skelton",
      claim_text:
        "Tub delivery arrived but size doesn't match the spec. Need to return and reorder correct dimensions.",
      claim_type: "issue",
    },
    {
      project_id: "proj_skelton",
      claim_text: "Budget for countertops approved around $6000 for stone material.",
      claim_type: "budget",
    },
    // White Residence claims -- different tub context (drain hookup)
    {
      project_id: "proj_white",
      claim_text: "Randy has one tub left to hook up the drain and finish the plumbing connections.",
      claim_type: "task_status",
    },
    {
      project_id: "proj_white",
      claim_text: "Exterior paint color approved by homeowner. Starting next week.",
      claim_type: "approval",
    },
    // Moss Residence claims -- vague, no specifics
    {
      project_id: "proj_moss",
      claim_text: "Need to check for any toilets or tubs that are still on order.",
      claim_type: "checklist",
    },
    {
      project_id: "proj_moss",
      claim_text: "Framing inspection passed. Moving on to rough-in.",
      claim_type: "milestone",
    },
  ];

  const results = computeClaimCrossref(transcript, candidates, journal_claims);

  console.log("Test 1: Skelton/White/Moss Floater Call");
  console.log("---------------------------------------");
  for (const r of results) {
    const name = candidates.find((c) => c.project_id === r.project_id)?.project_name;
    console.log(`  ${name}: score=${r.claim_crossref_score}`);
    console.log(`    matching_topics: [${r.matching_topics.join(", ")}]`);
    for (const mc of r.matching_claims) {
      console.log(
        `    claim: "${mc.claim_text.slice(0, 80)}..." [${mc.claim_type}] overlaps=[${mc.overlap_terms.join(", ")}]`,
      );
    }
    console.log();
  }

  // Assertions
  const skeltonScore = results.find((r) => r.project_id === "proj_skelton")!.claim_crossref_score;
  const whiteScore = results.find((r) => r.project_id === "proj_white")!.claim_crossref_score;
  const mossScore = results.find((r) => r.project_id === "proj_moss")!.claim_crossref_score;

  console.log("Assertions:");
  console.log(`  Skelton > White: ${skeltonScore} > ${whiteScore} = ${skeltonScore > whiteScore ? "PASS" : "FAIL"}`);
  console.log(`  Skelton > Moss:  ${skeltonScore} > ${mossScore} = ${skeltonScore > mossScore ? "PASS" : "FAIL"}`);
  console.log(`  White >= Moss:   ${whiteScore} >= ${mossScore} = ${whiteScore >= mossScore ? "PASS" : "FAIL"}`);
  console.log(`  Skelton is #1:   ${results[0].project_id === "proj_skelton" ? "PASS" : "FAIL"}`);
  // Note: transcript says "mystery white" and "stone" but not "marble" literally.
  // The compound term "mystery white" is the key differentiator.
  console.log(
    `  Skelton has "mystery white" compound: ${
      results.find((r) => r.project_id === "proj_skelton")!.matching_topics.includes("mystery white") ? "PASS" : "FAIL"
    }`,
  );
  console.log(
    `  Skelton has "stone" in topics: ${
      results.find((r) => r.project_id === "proj_skelton")!.matching_topics.includes("stone") ? "PASS" : "FAIL"
    }`,
  );
  console.log();

  // ---- TEST 2: No Claims Available ----
  console.log("Test 2: No Journal Claims");
  console.log("-------------------------");
  const emptyResults = computeClaimCrossref(transcript, candidates, []);
  const allZero = emptyResults.every((r) => r.claim_crossref_score === 0);
  console.log(`  All scores zero: ${allZero ? "PASS" : "FAIL"}`);
  console.log();

  // ---- TEST 3: Empty Transcript ----
  console.log("Test 3: Empty Transcript");
  console.log("------------------------");
  const emptyTranscript = computeClaimCrossref("", candidates, journal_claims);
  const allZero2 = emptyTranscript.every((r) => r.claim_crossref_score === 0);
  console.log(`  All scores zero: ${allZero2 ? "PASS" : "FAIL"}`);
  console.log();

  // ---- TEST 4: Dollar Amount Specificity ----
  console.log("Test 4: Dollar Amount Specificity");
  console.log("---------------------------------");
  const dollarTranscript = "we're looking at about $6000 for the countertop stone";
  const dollarClaims: JournalClaimInput[] = [
    {
      project_id: "proj_a",
      claim_text: "Countertop budget approved at $6000.",
      claim_type: "budget",
    },
    {
      project_id: "proj_b",
      claim_text: "General budget discussion ongoing for kitchen renovation.",
      claim_type: "budget",
    },
  ];
  const dollarCandidates = [
    { project_id: "proj_a", project_name: "Project A" },
    { project_id: "proj_b", project_name: "Project B" },
  ];
  const dollarResults = computeClaimCrossref(dollarTranscript, dollarCandidates, dollarClaims);
  const projAScore = dollarResults.find((r) => r.project_id === "proj_a")!.claim_crossref_score;
  const projBScore = dollarResults.find((r) => r.project_id === "proj_b")!.claim_crossref_score;
  console.log(`  Project A ($6000 match): ${projAScore}`);
  console.log(`  Project B (generic):     ${projBScore}`);
  console.log(`  A > B: ${projAScore > projBScore ? "PASS" : "FAIL"}`);
  console.log();

  // ---- TEST 5: Compound Term "mystery white" ----
  console.log("Test 5: Compound Term Matching (mystery white)");
  console.log("----------------------------------------------");
  const compoundTranscript = "she picked the mystery white marble for the master bath";
  const compoundClaims: JournalClaimInput[] = [
    {
      project_id: "proj_c",
      claim_text: "Customer selected mystery white marble from Arizona Tile.",
      claim_type: "material_selection",
    },
    {
      project_id: "proj_d",
      claim_text: "White paint selected for exterior trim.",
      claim_type: "material_selection",
    },
  ];
  const compoundCandidates = [
    { project_id: "proj_c", project_name: "Project C (has mystery white)" },
    { project_id: "proj_d", project_name: "Project D (has white only)" },
  ];
  const compoundResults = computeClaimCrossref(compoundTranscript, compoundCandidates, compoundClaims);
  const projCScore = compoundResults.find((r) => r.project_id === "proj_c")!.claim_crossref_score;
  const projDScore = compoundResults.find((r) => r.project_id === "proj_d")!.claim_crossref_score;
  console.log(`  Project C (mystery white match): ${projCScore}`);
  console.log(`  Project D (white only):          ${projDScore}`);
  console.log(`  C > D: ${projCScore > projDScore ? "PASS" : "FAIL"}`);
  console.log();

  // ---- TEST 6: Single Candidate (degenerate case) ----
  console.log("Test 6: Single Candidate");
  console.log("------------------------");
  const singleResults = computeClaimCrossref(
    transcript,
    [{ project_id: "proj_skelton", project_name: "Skelton Residence" }],
    journal_claims.filter((c) => c.project_id === "proj_skelton"),
  );
  console.log(`  Score: ${singleResults[0].claim_crossref_score}`);
  console.log(`  Has matching topics: ${singleResults[0].matching_topics.length > 0 ? "PASS" : "FAIL"}`);
  console.log();

  // ---- TEST 7: Same generic term in ALL projects (low IDF) ----
  console.log("Test 7: Generic Term (low IDF -- appears in all projects)");
  console.log("---------------------------------------------------------");
  const genericTranscript = "we need to finish the tub installation";
  const genericClaims: JournalClaimInput[] = [
    { project_id: "proj_e", claim_text: "Tub installed in master bath.", claim_type: "task" },
    { project_id: "proj_f", claim_text: "Tub delivery scheduled for Friday.", claim_type: "task" },
    { project_id: "proj_g", claim_text: "Tub surround tile selected.", claim_type: "task" },
  ];
  const genericCandidates = [
    { project_id: "proj_e", project_name: "Project E" },
    { project_id: "proj_f", project_name: "Project F" },
    { project_id: "proj_g", project_name: "Project G" },
  ];
  const genericResults = computeClaimCrossref(genericTranscript, genericCandidates, genericClaims);
  // All should score relatively low and similar because "tub" appears everywhere
  const maxGeneric = Math.max(...genericResults.map((r) => r.claim_crossref_score));
  const minGeneric = Math.min(...genericResults.map((r) => r.claim_crossref_score));
  console.log(`  Scores: ${genericResults.map((r) => r.claim_crossref_score).join(", ")}`);
  console.log(
    `  Max-Min spread <= 0.15: ${(maxGeneric - minGeneric) <= 0.15 ? "PASS" : "FAIL"} (spread=${
      (maxGeneric - minGeneric).toFixed(3)
    })`,
  );
  console.log(`  All scores below 0.5: ${maxGeneric < 0.5 ? "PASS" : "FAIL"}`);
  console.log();

  console.log("=== Test Suite Complete ===");
}

// Run tests if this file is executed directly
// In Deno: deno run FIX_claim_crossref.ts
// The tests will NOT run when imported as a module.
const _isMainModule = typeof Deno !== "undefined"
  ? (Deno as any).mainModule ===
      `file://${(Deno as any).cwd?.() || ""}/${new URL(import.meta.url).pathname.split("/").pop()}` ||
    import.meta.url.endsWith("FIX_claim_crossref.ts")
  : true;

if (_isMainModule) {
  runTests();
}
