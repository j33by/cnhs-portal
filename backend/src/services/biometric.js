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

// Group punches per person per day, first = IN, last = OUT (the device has no in/out flag).
function dailyFromPunches(punches) {
  const map = new Map();
  for (const p of punches) {
    const k = p.biometric_id + '|' + p.date;
    if (!map.has(k)) map.set(k, { biometric_id: p.biometric_id, date: p.date, times: [] });
    map.get(k).times.push(p.time);
  }
  return [...map.values()].map(d => {
    d.times.sort();
    return { biometric_id: d.biometric_id, date: d.date, time_in: d.times[0],
             time_out: d.times.length > 1 ? d.times[d.times.length - 1] : null, punches: d.times.length };
  });
}
module.exports = { parseLogs, parseEmployeeForm, dailyFromPunches };
