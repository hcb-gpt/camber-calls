// transcribe-deepgram v5
// CHANGELOG:
// - v5: Edge function now writes to transcripts_comparison directly (with words array)
// - v4: Rename transcript_variant values: 'pre'/'post' → 'keywords_off'/'keywords_on' for clarity
// - v3: Add request-body toggle `keywords_enabled` (default true) to gate dynamic vocab injection.
//       Emit `transcript_variant` (pre/post) + `keywords_enabled` in response metadata for downstream persistence.
// - v2: Dynamic vocab injection from `transcription_vocab`.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type VocabRow = { term: string; boost: number | null };

type TranscriptVariant = 'keywords_off' | 'keywords_on';

type RequestBody = {
  recording_url?: string;
  interaction_id?: string;
  keywords_enabled?: boolean;
};

function normalizeTerm(t: unknown): string {
  if (typeof t !== 'string') return '';
  return t.trim();
}

function coerceBoost(b: unknown): number {
  const n = typeof b === 'number' ? b : (typeof b === 'string' ? Number(b) : NaN);
  if (!Number.isFinite(n)) return 1;
  return n;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'method_not_allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = (await req.json()) as RequestBody;
    const recording_url = body?.recording_url;
    const interaction_id = body?.interaction_id;
    const keywords_enabled = body?.keywords_enabled ?? true;
    const transcript_variant: TranscriptVariant = keywords_enabled ? 'keywords_on' : 'keywords_off';

    if (!recording_url) {
      return new Response(JSON.stringify({ ok: false, error: 'missing_recording_url' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Get API key
    const { data: keyRow, error: keyError } = await supabase
      .from('api_keys')
      .select('api_key')
      .eq('service', 'deepgram')
      .single();

    if (keyError || !keyRow?.api_key) {
      return new Response(JSON.stringify({ ok: false, error: 'missing_api_key' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const DEEPGRAM_API_KEY = keyRow.api_key as string;
    const DEEPGRAM_MODEL = Deno.env.get('DEEPGRAM_MODEL') || 'nova-2';

    // Fetch active vocab (gated)
    let vocabQueryMs = 0;
    let vocabTerms: Array<[string, number]> = [];

    if (!keywords_enabled) {
      console.log('keywords_enabled=false, skipping vocab query/injection');
    } else {
      const vocabQueryStart = Date.now();
      const { data: vocabData, error: vocabError } = await supabase
        .from('transcription_vocab')
        .select('term, boost')
        .eq('active', true)
        .order('boost', { ascending: false })
        .limit(100);

      vocabQueryMs = Date.now() - vocabQueryStart;

      if (vocabError) {
        console.warn('transcription_vocab query failed:', vocabError.message);
      }

      // Dedupe terms, prefer highest boost
      const vocabMap = new Map<string, number>();
      for (const row of (vocabData || []) as VocabRow[]) {
        const term = normalizeTerm(row.term);
        if (!term) continue;
        const boost = coerceBoost(row.boost);
        const existing = vocabMap.get(term);
        if (existing === undefined || boost > existing) {
          vocabMap.set(term, boost);
        }
      }

      vocabTerms = Array.from(vocabMap.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 100);

      console.log(
        `keywords_enabled=true vocab_terms=${vocabTerms.length} vocab_query_ms=${vocabQueryMs} model=${DEEPGRAM_MODEL}`,
      );
    }

    const startTime = Date.now();

    // Fetch audio first (Deepgram prefers direct audio)
    console.log(`Fetching audio from: ${recording_url}`);
    const audioResponse = await fetch(recording_url);

    if (!audioResponse.ok) {
      return new Response(JSON.stringify({ ok: false, error: 'fetch_failed', status: audioResponse.status }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const audioBuffer = await audioResponse.arrayBuffer();
    const audioSizeBytes = audioBuffer.byteLength;
    console.log(`Audio fetched: ${(audioSizeBytes / 1024 / 1024).toFixed(2)} MB`);

    // Call Deepgram API
    const deepgramUrl = new URL('https://api.deepgram.com/v1/listen');
    deepgramUrl.searchParams.set('model', DEEPGRAM_MODEL);
    deepgramUrl.searchParams.set('diarize', 'true');
    deepgramUrl.searchParams.set('punctuate', 'true');
    deepgramUrl.searchParams.set('utterances', 'true');
    deepgramUrl.searchParams.set('smart_format', 'true');

    // Inject dynamic vocabulary
    let vocab_injected_param: 'keywords' | 'keyterm' | null = null;
    const isNova3 = /^nova-3/i.test(DEEPGRAM_MODEL);

    if (keywords_enabled && vocabTerms.length > 0) {
      if (isNova3) {
        vocab_injected_param = 'keyterm';
        // Nova-3 uses keyterm prompting; boost weights are not supported by the API
        for (const [term] of vocabTerms) deepgramUrl.searchParams.append('keyterm', term);
      } else {
        vocab_injected_param = 'keywords';
        // Nova-2 (and other supported models) use keyword boosting with intensifiers
        for (const [term, boost] of vocabTerms) {
          // Deepgram expects keywords=TERM:INTENSIFIER
          deepgramUrl.searchParams.append('keywords', `${term}:${boost}`);
        }
      }
    }

    console.log('Calling Deepgram API...');
    const deepgramResponse = await fetch(deepgramUrl.toString(), {
      method: 'POST',
      headers: {
        'Authorization': `Token ${DEEPGRAM_API_KEY}`,
        'Content-Type': 'audio/mpeg',
      },
      body: audioBuffer,
    });

    if (!deepgramResponse.ok) {
      const errorText = await deepgramResponse.text();
      console.error('Deepgram API error:', errorText);
      return new Response(JSON.stringify({ ok: false, error: 'deepgram_api_failed', details: errorText }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const deepgramResult = await deepgramResponse.json();
    const transcriptionMs = Date.now() - startTime;
    console.log(`Deepgram completed in ${transcriptionMs}ms`);

    // Extract results
    const channel = deepgramResult.results?.channels?.[0];
    const alternative = channel?.alternatives?.[0];

    // Format transcript with speaker labels from utterances
    let formattedTranscript = '';
    const speakerSet = new Set<number>();

    if (deepgramResult.results?.utterances) {
      for (const utterance of deepgramResult.results.utterances) {
        const speaker = `SPEAKER_${utterance.speaker}`;
        speakerSet.add(utterance.speaker);
        formattedTranscript += `${speaker}: ${utterance.transcript}\n`;
      }
    } else if (alternative?.transcript) {
      formattedTranscript = alternative.transcript;
    }

    // Extract word-level data
    const words = alternative?.words?.map((w: any) => ({
      word: w.word,
      start: w.start,
      end: w.end,
      speaker: w.speaker,
      confidence: w.confidence,
    })) || null;

    // Persist to transcripts_comparison (v5: edge function owns the write)
    if (interaction_id) {
      try {
        await supabase.from('transcripts_comparison').upsert({
          interaction_id,
          engine: 'deepgram',
          model: `deepgram-${DEEPGRAM_MODEL}`,
          transcript: formattedTranscript.trim(),
          words,
          transcript_variant,
          audio_size_bytes: audioSizeBytes,
          duration_seconds: deepgramResult.metadata?.duration || null,
          word_count: words?.length || 0,
          has_speaker_labels: true,
          speaker_count: speakerSet.size,
          transcription_ms: transcriptionMs,
          cost_cents: Math.ceil(((deepgramResult.metadata?.duration || 0) / 60) * 0.25),
        }, { onConflict: 'interaction_id,engine' });
      } catch (e) {
        console.warn('transcripts_comparison upsert failed:', (e as Error).message);
      }
    }

    // Response includes receipt/metadata fields for downstream persistence
    return new Response(JSON.stringify({
      ok: true,
      interaction_id,
      engine: 'deepgram',
      transcript: formattedTranscript.trim(),
      transcript_compressed: null,
      model: `deepgram-${DEEPGRAM_MODEL}`,
      audio_size_bytes: audioSizeBytes,
      duration_seconds: deepgramResult.metadata?.duration || null,
      input_tokens: null,
      output_tokens: null,
      words,
      speaker_count: speakerSet.size,
      transcription_ms: transcriptionMs,
      confidence: alternative?.confidence || null,

      // keywords_off/keywords_on control + receipt
      transcript_variant,
      keywords_enabled,
      metadata: {
        transcript_variant,
        keywords_enabled,
      },

      // Debug/perf
      vocab_terms: vocabTerms.length,
      vocab_query_ms: vocabQueryMs,
      vocab_injected_param,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error:', error);
    return new Response(JSON.stringify({ ok: false, error: 'internal_error', details: (error as Error).message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
