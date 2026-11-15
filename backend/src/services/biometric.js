// Parses the files the fingerprint terminal exports to the USB stick.
const XLSX = require('xlsx');

// Attendance_Logs.txt : "ID<TAB>Name<TAB>Dept.<TAB> 2026-11-02     10:28:36<TAB>Device ID"
function parseLogs(text) {
  const out = [];
  for (const line of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
    const c = line.split('\t');
    if (c.length < 4 || !/^\d+$/.test(c[0].trim())) continue;       // skips header + blanks
    const m = c[3].match(/(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})/);
    if (!m) continue;
    out.push({ biometric_id: +c[0], name: (c[1] || '').trim(), dept: (c[2] || '').trim(),
               date: m[1], time: m[2], device_id: +(c[4] || 1) || 1 });
  }
  return out;
}

// Employee_Form.xls -> people on the device (ID, name, dept no.)
function parseEmployeeForm(buf) {
  const wb = XLSX.read(buf, { type: 'buffer' });
  const ws = wb.Sheets['Employee Form']; if (!ws) return [];
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
  const people = [];
  for (const r of rows.slice(8)) if (r[0] !== '' && !isNaN(+r[0])) people.push({ biometric_id: +r[0], name: String(r[1]), dept_no: +r[2] || null });
  return people;
}

const mins = t => { const [h, m] = t.split(':'); return +h * 60 + +m; };
// The terminal has no IN/OUT flag: first punch = IN. Last punch counts as OUT only if it is 30+ min later,
// so a double-tap right after arriving is not reported as "left school".
function summarizeTimes(times) {
  const t = [...times].sort();
  return { time_in: t[0], time_out: t.length > 1 && mins(t[t.length - 1]) - mins(t[0]) >= 30 ? t[t.length - 1] : null, punches: t.length };
}
function dailyFromPunches(punches) {
  const map = new Map();
  for (const p of punches) { const k = p.biometric_id + '|' + p.date; if (!map.has(k)) map.set(k, { biometric_id: p.biometric_id, date: p.date, times: [] }); map.get(k).times.push(p.time); }
  return [...map.values()].map(d => ({ biometric_id: d.biometric_id, date: d.date, ...summarizeTimes(d.times) }));
}
module.exports = { parseLogs, parseEmployeeForm, dailyFromPunches, summarizeTimes };
