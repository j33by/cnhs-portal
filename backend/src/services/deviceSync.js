// Keeps the fingerprint terminal's "employees" and the app's students in step.
//   autoLinkByName : people already enrolled on the terminal (device_people) are matched to students by NAME and linked automatically
//   ensureBioIds   : every enrolled student that still has no device ID gets one (above every ID the terminal / punches already use)
//   cleanName      : names as the terminal wants them (plain ASCII, max 24 characters)
const { relinkPunches } = require('./attendance');

const strip = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
const norm = s => strip(s).toUpperCase().replace(/[^A-Z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
const key = s => norm(s).split(' ').filter(Boolean).sort().join(' ');
const cleanName = (s, n = 24) => strip(s).replace(/ñ/gi, m => (m === 'ñ' ? 'n' : 'N')).replace(/[^A-Za-z0-9 .'-]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n).trim();

const chunk = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };

// device IDs that already have punches (those can never be changed safely)
async function punchedIds(sb, ids) {
  const out = new Set();
  for (const c of chunk(ids, 200)) {
    const { data } = await sb.from('attendance').select('biometric_id').in('biometric_id', c);
    for (const r of data || []) out.add(r.biometric_id);
  }
  return out;
}

async function autoLinkByName(sb) {
  const [{ data: devs }, { data: stu }] = await Promise.all([
    sb.from('device_people').select('biometric_id,name,ignored'),
    sb.from('students').select('id,first_name,middle_name,last_name,section_id,biometric_id').eq('status', 'enrolled')]);
  if (!devs?.length || !stu?.length) return { linked: 0 };
  const deviceIds = new Set(devs.map(d => d.biometric_id));
  const used = new Set(stu.filter(s => s.biometric_id).map(s => s.biometric_id));
  // students that may be linked: no device ID yet, or an ID that the terminal has never seen and that has no punches (assigned by the app, unconfirmed)
  const assigned = stu.filter(s => s.biometric_id && !deviceIds.has(s.biometric_id));
  const punched = await punchedIds(sb, assigned.map(s => s.biometric_id));
  const open = stu.filter(s => !s.biometric_id || (!deviceIds.has(s.biometric_id) && !punched.has(s.biometric_id)));
  const free = devs.filter(d => !d.ignored && d.name && !used.has(d.biometric_id));
  const keysOf = s => [...new Set([key(`${s.first_name} ${s.last_name}`), key(`${s.first_name} ${s.middle_name || ''} ${s.last_name}`)])];
  const byKey = new Map();
  for (const s of open) for (const k of keysOf(s)) { if (!byKey.has(k)) byKey.set(k, new Set()); byKey.get(k).add(s.id); }
  const sById = new Map(open.map(s => [s.id, s]));
  const pick = new Map();                                                    // student -> [device ids]
  const devPick = new Map();                                                 // device -> [students]
  for (const d of free) {
    let ids = byKey.get(key(d.name));
    if (!ids && norm(d.name).length >= 22) {                                 // the terminal cut a long name at 24 characters
      ids = new Set(open.filter(s => norm(`${s.first_name} ${s.last_name}`).startsWith(norm(d.name))).map(s => s.id));
      if (!ids.size) ids = undefined;
    }
    if (!ids) continue;
    devPick.set(d.biometric_id, [...ids]);
    for (const id of ids) { if (!pick.has(id)) pick.set(id, []); pick.get(id).push(d.biometric_id); }
  }
  let linked = 0;
  for (const [did, sids] of devPick) {
    if (sids.length !== 1 || pick.get(sids[0]).length !== 1) continue;      // same name twice: a teacher decides (fingerprint icon in the advisory list)
    const s = sById.get(sids[0]);
    const { error } = await sb.from('students').update({ biometric_id: did }).eq('id', s.id);
    if (error) continue;                                                     // ID taken in the meantime
    await relinkPunches(sb, s, did).catch(() => {}); linked++;
  }
  return { linked };
}

async function maxBioId(sb) {
  let max = 0;
  for (const [t, c] of [['students', 'biometric_id'], ['device_people', 'biometric_id'], ['attendance', 'biometric_id']]) {
    const { data } = await sb.from(t).select(c).not(c, 'is', null).order(c, { ascending: false }).limit(1);
    if (data?.[0]) max = Math.max(max, data[0][c]);
  }
  return max;
}

async function ensureBioIds(sb) {
  const { data: todo } = await sb.from('students').select('id').eq('status', 'enrolled').is('biometric_id', null).order('created_at', { ascending: true });
  if (!todo?.length) return { assigned: 0 };
  let next = (await maxBioId(sb)) + 1, assigned = 0;
  for (const s of todo) {
    for (let tries = 0; tries < 5; tries++) {
      const { error } = await sb.from('students').update({ biometric_id: next }).eq('id', s.id).is('biometric_id', null);
      next++;
      if (!error) { assigned++; break; }                                     // unique clash with a concurrent sign-up: try the next number
    }
  }
  return { assigned };
}

// everything the form needs, in the order that avoids duplicate people on the terminal
// Every section is one terminal department (1-16): give each section that has none the lowest free number.
async function ensureDepts(sb) {
  const { data: se } = await sb.from('sections').select('id,biometric_dept_no').order('created_at');
  const used = new Set((se || []).map(s => s.biometric_dept_no).filter(Boolean)); let n = 0;
  for (const s of (se || []).filter(s => !s.biometric_dept_no)) {
    let d = 1; while (used.has(d) && d <= 16) d++; if (d > 16) break;
    const { error } = await sb.from('sections').update({ biometric_dept_no: d }).eq('id', s.id); if (!error) { used.add(d); n++; } }
  return n;
}

async function prepare(sb) {
  await ensureDepts(sb);
  const a = await autoLinkByName(sb), b = await ensureBioIds(sb);
  return { linked: a.linked, assigned: b.assigned };
}
module.exports = { autoLinkByName, ensureBioIds, prepare, cleanName, norm };
