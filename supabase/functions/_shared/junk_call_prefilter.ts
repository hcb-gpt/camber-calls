export interface JunkCallPrefilterInput {
  transcript: string | null | undefined;
  durationSeconds?: number | null;
  minWordCount?: number;
  shortDurationSeconds?: number;
}

export interface JunkCallPrefilterResult {
  isJunk: boolean;
  reasonCodes: string[];
  signalSummary: string[];
  wordCount: number;
  speakerTurns: number;
  durationSeconds: number | null;
}

const DEFAULT_MIN_WORD_COUNT = 20;
const DEFAULT_SHORT_DURATION_SECONDS = 15;
const VOICEMAIL_PATTERNS: Array<{ code: string; re: RegExp }> = [
  { code: "voicemail_leave_message", re: /\bleave (?:me )?(?:a )?message\b/i },
  { code: "voicemail_mailbox_full", re: /\bmailbox is (?:full|not set up)\b/i },
  { code: "voicemail_not_available", re: /\b(?:cannot|can't|unable to)\s+take your call\b/i },
  { code: "voicemail_after_tone", re: /\bafter the tone\b/i },
  { code: "voicemail_record_message", re: /\bplease record your message\b/i },
];
const CONNECTION_FAILURE_PATTERNS: Array<{ code: string; re: RegExp }> = [
  { code: "connection_bad_service", re: /\bbad service\b/i },
  { code: "connection_call_dropped", re: /\bcall (?:dropped|failed|disconnected)\b/i },
  { code: "connection_cant_hear", re: /\b(?:can you|can't|cannot)\s+hear (?:me|you)\b/i },
];
const SUBSTANTIVE_PATTERNS: RegExp[] = [
  /\bestimate\b/i,
  /\bproposal\b/i,
  /\bcontract\b/i,
  /\binvoice\b/i,
  /\bdeposit\b/i,
  /\bpermit\b/i,
  /\bschedule\b/i,
  /\bchange order\b/i,
  /\binstall(?:ation)?\b/i,
  /\bcabinet(?:s)?\b/i,
  /\bcountertop(?:s)?\b/i,
  /\btile\b/i,
  /\bplumbing\b/i,
  /\belectrical\b/i,
  /\$\s*\d+/,
];

export function normalizeDurationSeconds(raw: unknown): number | null {
  if (raw == null) return null;
  const num = Number(raw);
  if (!Number.isFinite(num) || num <= 0) return null;
  if (num > 10_000) return Math.round(num / 1000);
  return Math.round(num);
}

function countSpeakerTurns(transcript: string): number {
  const re = /(?:^|\n)\s*[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s*:/g;
  let count = 0;
  while (re.exec(transcript) !== null) count += 1;
  return count;
}

function countWords(transcript: string): number {
  const tokens = transcript.match(/[a-z0-9']+/gi);
  return tokens ? tokens.length : 0;
}

export function evaluateJunkCallPrefilter(input: JunkCallPrefilterInput): JunkCallPrefilterResult {
  const transcript = String(input.transcript || "").trim();
  const durationSeconds = normalizeDurationSeconds(input.durationSeconds ?? null);
  const minWordCount = input.minWordCount ?? DEFAULT_MIN_WORD_COUNT;
  const shortDurationSeconds = input.shortDurationSeconds ?? DEFAULT_SHORT_DURATION_SECONDS;

  const wordCount = countWords(transcript);
  const speakerTurns = countSpeakerTurns(transcript);
  const lowWordCount = wordCount > 0 && wordCount < minWordCount;
  const singleSpeakerTurn = speakerTurns <= 1;
  const shortDuration = durationSeconds != null && durationSeconds < shortDurationSeconds;

  const voicemailMatches = VOICEMAIL_PATTERNS.filter((p) => p.re.test(transcript)).map((p) => p.code);
  const connectionMatches = CONNECTION_FAILURE_PATTERNS.filter((p) => p.re.test(transcript)).map((p) => p.code);
  const hasSubstantiveSignal = SUBSTANTIVE_PATTERNS.some((re) => re.test(transcript));

  const junkByVoicemail = voicemailMatches.length > 0 && wordCount <= 80;
  const junkByConnectionFailure = connectionMatches.length > 0 && wordCount <= 40 && !hasSubstantiveSignal;
  const junkByMinimalContent = lowWordCount && (singleSpeakerTurn || shortDuration) && !hasSubstantiveSignal;
  const isJunk = junkByVoicemail || junkByConnectionFailure || junkByMinimalContent;

  const reasonCodes: string[] = [];
  if (isJunk) {
    reasonCodes.push("junk_call_filtered");
    if (junkByVoicemail) reasonCodes.push("voicemail_pattern");
    if (junkByConnectionFailure) reasonCodes.push("connection_failure_pattern");
    if (lowWordCount) reasonCodes.push("low_word_count");
    if (singleSpeakerTurn) reasonCodes.push("single_speaker_turn");
    if (shortDuration) reasonCodes.push("short_duration");
  }

  const signalSummary: string[] = [];
  signalSummary.push(`word_count=${wordCount}`);
  signalSummary.push(`speaker_turns=${speakerTurns}`);
  if (durationSeconds != null) signalSummary.push(`duration_seconds=${durationSeconds}`);
  if (voicemailMatches.length > 0) signalSummary.push(`voicemail_hits=${voicemailMatches.join("|")}`);
  if (connectionMatches.length > 0) signalSummary.push(`connection_hits=${connectionMatches.join("|")}`);
  if (hasSubstantiveSignal) signalSummary.push("substantive_signal_present");

  return {
    isJunk,
    reasonCodes: Array.from(new Set(reasonCodes)),
    signalSummary,
    wordCount,
    speakerTurns,
    durationSeconds,
  };
}
