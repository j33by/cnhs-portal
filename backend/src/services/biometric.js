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

// "All Report.xls" -> punches + people. The terminal writes one block per person on the 'Attendance Logs' sheet:
//   ["ID","",<id>,...,"Name","",<name>] / day numbers / weekday names / one cell per day with HH:MM punches separated by new lines.
// Day columns start at the first date of the range in "Date  yyyy-mm-dd ~ yyyy-mm-dd" (a range may cross a month end).
function parseAllReport(buf) {
  const wb = XLSX.read(buf, { type: 'buffer' }), punches = [], people = new Map();
  const ws = wb.Sheets['Attendance Logs']; if (!ws) return { punches, people: [] };
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' }).map(r => r.map(c => (c === null || c === undefined ? '' : c)));
  let start = null;
  for (const r of rows) { const m = r.map(String).join(' ').match(/(\d{4})-(\d{2})-(\d{2})\s*~/); if (m) { start = Date.UTC(+m[1], +m[2] - 1, +m[3]); break; } }
  if (start === null) return { punches, people: [] };
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i]; if (String(r[0]).trim() !== 'ID') continue;
    const idCell = r.slice(1).find(c => /^\d+$/.test(String(c).trim())); if (idCell === undefined) continue;
    const ni = r.findIndex(c => String(c).trim() === 'Name'); const name = ni >= 0 ? String(r.slice(ni + 1).find(c => String(c).trim()) || '').trim() : '';
    const id = +idCell; people.set(id, { biometric_id: id, name });
    for (let j = i + 1; j < rows.length && String(rows[j][0]).trim() !== 'ID'; j++) {
      rows[j].forEach((cell, col) => {
        const t = String(cell); if (!/\d{1,2}:\d{2}/.test(t)) return;
        const date = new Date(start + col * 864e5).toISOString().slice(0, 10);
        for (const m of t.matchAll(/(\d{1,2}):(\d{2})/g)) punches.push({ biometric_id: id, name, dept: '', date, time: m[1].padStart(2, '0') + ':' + m[2] + ':00', device_id: 1 });
      });
    }
  }
  return { punches, people: [...people.values()] };
}

// Employee Form.xls -> people on the device (ID, name, dept no.)
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
module.exports = { parseAllReport, parseLogs, parseEmployeeForm, dailyFromPunches, summarizeTimes };
