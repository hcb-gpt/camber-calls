/**
 * process-call Edge Function v3.8.8
 * Full v3.6 pipeline in Supabase
 *
 * @version 3.8.8
 * @date 2026-01-30
 * @fix Inline transcript scan (Option C) - removes RPC schema cache dependency
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GATE = { PASS: 'PASS', SKIP: 'SKIP', NEEDS_REVIEW: 'NEEDS_REVIEW' };
const ID_PATTERN = /^cll_[a-zA-Z0-9_]+$/;

function m1(raw: any) {
  const a = { ...raw };
  if (a.transcript_text && !a.transcript) a.transcript = a.transcript_text;
  if (!a.interaction_id && a.call_id) a.interaction_id = a.call_id;
  return a;
}

function m4(n: any) {
  const r: string[] = [];
  if (n.interaction_id && !ID_PATTERN.test(n.interaction_id)) r.push('G1_ID_MALFORMED');
  if ((n.transcript || '').length < 10) r.push('G4_EMPTY_TRANSCRIPT');
  if (!n.event_at_utc && !n.call_start_utc) r.push('G4_TIMESTAMP_MISSING');
  return { decision: r.length > 0 ? GATE.NEEDS_REVIEW : GATE.PASS, reasons: r };
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  const run_id = `run_${t0}_${Math.random().toString(36).slice(2, 8)}`;
  
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'POST only' }), { status: 405, headers: { 'Content-Type': 'application/json' } });
  
  let raw: any;
  try { raw = await req.json(); } catch { return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: { 'Content-Type': 'application/json' } }); }
  
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const iid = raw.interaction_id || raw.call_id || `unknown_${run_id}`;
  const id_gen = !raw.interaction_id && !raw.call_id;
  
  let audit_id: number | null = null, cr_uuid: string | null = null;
  let contact_id: string | null = null, contact_name: string | null = null;
  let project_id: string | null = null, project_name: string | null = null;
  let project_source: string | null = null;
  
  try {
    // IDEMPOTENCY
    if (!id_gen) {
      const { error } = await db.from('idempotency_keys').insert({ key: iid, interaction_id: iid, source: raw.source || 'edge', router_version: 'v3.8.8' });
      if (error && (error.message?.includes('duplicate') || error.message?.includes('23505'))) {
        await db.from('event_audit').insert({ interaction_id: iid, gate_status: 'SKIP', gate_reasons: ['G1_DUPLICATE_EXACT'], source_system: 'edge_v3.8', source_run_id: run_id, pipeline_version: 'v3.8' });
        return new Response(JSON.stringify({ ok: true, run_id, decision: 'SKIP', reason: 'duplicate', interaction_id: iid, ms: Date.now() - t0 }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
    }
    
    // AUDIT STARTED
    const { data: ad } = await db.from('event_audit').insert({ interaction_id: iid, gate_status: 'STARTED', gate_reasons: [], source_system: 'edge_v3.8', source_run_id: run_id, pipeline_version: 'v3.8', processed_by: 'process-call', persisted_to_calls_raw: false, i1_phone_present: !!(raw.from_phone || raw.to_phone), i2_unique_id: !id_gen }).select('id').single();
    if (ad) audit_id = ad.id;
    
    // M1
    const n = m1(raw);
    const phone = n.to_phone || n.other_party_phone || n.contact_phone;
    
    // CONTACT
    if (phone) {
      const { data } = await db.rpc('lookup_contact_by_phone', { p_phone: phone });
      if (data?.[0]) { contact_id = data[0].contact_id; contact_name = data[0].contact_name; }
    }
    
    // PROJECT - first try transcript scan (more accurate), then fallback to contact link
    if (n.transcript) {
      // Inline transcript scan: find project names mentioned in transcript
      const { data: projects } = await db.from('projects').select('id, name');
      if (projects) {
        const transcript_lower = n.transcript.toLowerCase();
        for (const p of projects) {
          // Match project name or key words (e.g., "Winships" matches "Winship Residence")
          const name_lower = p.name.toLowerCase();
          const name_words = name_lower.split(/\s+/);
          const first_word = name_words[0];
          // Check full name or first word (handles "Winships" -> "Winship Residence")
          if (transcript_lower.includes(name_lower) ||
              (first_word.length >= 4 && transcript_lower.includes(first_word))) {
            project_id = p.id;
            project_name = p.name;
            project_source = 'transcript_scan';
            break;
          }
        }
      }
    }
    // Fallback: contact link (only if transcript scan found nothing)
    if (!project_id && contact_id) {
      const { data: links } = await db.from('project_contacts').select('project_id').eq('contact_id', contact_id).limit(1);
      if (links?.[0]) {
        const { data: p } = await db.from('projects').select('id, name').eq('id', links[0].project_id).single();
        if (p) { project_id = p.id; project_name = p.name; project_source = 'contact_link'; }
      }
    }
    
    // GATE
    const g = m4(n);
    
    // CALLS_RAW
    const { data: cr } = await db.from('calls_raw').upsert({ interaction_id: iid, channel: 'call', direction: n.direction || null, owner_phone: n.from_phone || null, other_party_phone: phone || null, event_at_utc: n.event_at_utc || null, transcript: n.transcript || null, recording_url: n.recording_url || n.beside_note_url || null, pipeline_version: 'v3.8', raw_snapshot_json: { run_id, v: 'v3.8.8', gate: g.decision, contact_id, project_id, project_source } }, { onConflict: 'interaction_id' }).select('id').single();
    if (cr) cr_uuid = cr.id;
    
    // INTERACTIONS
    if (g.decision === 'PASS' || g.decision === 'NEEDS_REVIEW') {
      await db.from('interactions').upsert({
        interaction_id: iid,
        channel: 'call',
        contact_id: contact_id || null,
        contact_name: contact_name || null,
        contact_phone: phone || null,
        owner_phone: n.from_phone || null,
        project_id: project_id || null,
        event_at_utc: n.event_at_utc || null,
        needs_review: g.decision === 'NEEDS_REVIEW',
        review_reasons: g.reasons,
        project_attribution_confidence: project_id ? 0.8 : null,
        transcript_chars: n.transcript?.length || 0
      }, { onConflict: 'interaction_id' });
    }
    
    // CONTACT STATS (optional, ignore errors)
    if (contact_id) {
      try { await db.rpc('update_contact_interaction_stats', { p_contact_id: contact_id }); } catch {}
    }
    
    // AUDIT FINAL
    if (audit_id) await db.from('event_audit').update({ gate_status: g.decision, gate_reasons: g.reasons, persisted_to_calls_raw: !!cr_uuid, calls_raw_uuid: cr_uuid }).eq('id', audit_id);
    
    return new Response(JSON.stringify({ ok: true, run_id, interaction_id: iid, decision: g.decision, reasons: g.reasons, contact_id, contact_name, project_id, project_name, project_source, audit_id, cr_uuid, ms: Date.now() - t0 }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    
  } catch (e: any) {
    if (audit_id) await db.from('event_audit').update({ gate_status: 'ERROR', gate_reasons: [e.message || 'unknown'] }).eq('id', audit_id);
    return new Response(JSON.stringify({ ok: false, run_id, interaction_id: iid, error: e.message, ms: Date.now() - t0 }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
