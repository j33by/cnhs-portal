// Rebuilds "Employee Form.xls" (the two sheets the terminal reads and uploads) from the database.
// The layout, merged cells, rules block and notes copy the file the terminal itself exports (checked against a real export),
// because the terminal refuses an upload whose sheets differ from its own template.
const XLSX = require('xlsx');
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const NDAYS = 31;                                  // schedule window of the terminal's template: columns E..AI (merged date cell E6:AI6)
const WEEK = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const ascii = (s, n) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9 ._-]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n).trim();

// people: [{biometric_id,name,dept_no}]  sections: [{dept_no,name}]  slots: [{dept_no,day_of_week,start,end}]
function buildEmployeeForm({ people, sections, slots, company = 'cnhs', start = new Date() }) {
  // One "school day" shift per distinct first-start/last-end span (the terminal allows 10 shifts)
  const span = new Map();                          // dept|day -> [min,max]
  for (const s of slots) { const k = s.dept_no + '|' + s.day_of_week, v = span.get(k);
    span.set(k, v ? [v[0] < s.start ? v[0] : s.start, v[1] > s.end ? v[1] : s.end] : [s.start, s.end]); }
  const shifts = []; const shiftOf = ([a, b]) => { let i = shifts.findIndex(x => x[0] === a && x[1] === b);
    if (i < 0) { if (shifts.length >= 10) return 0; shifts.push([a, b]); i = shifts.length - 1; } return i + 1; };
  const deptWeek = {}; for (const [k, v] of span) { const [d, w] = k.split('|'); (deptWeek[d] ||= Array(7).fill(0))[+w] = shiftOf(v); }

  const iso = d => d.toISOString().slice(0, 10);
  const blank = n => Array(n).fill('');
  const days = [...Array(NDAYS)].map((_, i) => new Date(start.getTime() + i * 864e5));

  // ---- Sheet 1: Employee Form
  const A = [['Employee Form'], ['Remark:'],
    ['1.Upload employee information, please fill in the information under the * column;'],
    ['2.Edit employee scheduling upload:1-10 Shifts,25-Leave,26-Business trips,Empty/0-Holidays;'],
    ['3.Authority:0-Employee, 1-Admin;'],
    ['Date(Example:2000-01-01)', '', '', '', iso(start)],
    ['*ID', '*Name', '*Department(1-16)', '*Authority', ...days.map(d => d.getUTCDate())],
    ['', '', '', '', ...days.map(d => WEEK[d.getUTCDay()])]];
  const seen = new Set();
  for (const p of people) {
    const id = Math.trunc(+p.biometric_id); if (!(id >= 1) || seen.has(id)) continue; seen.add(id);
    const dept = Math.min(16, Math.max(1, Math.trunc(+p.dept_no) || 1));
    A.push([id, ascii(p.name, 24) || 'Student ' + id, dept, 0, ...blank(NDAYS)]);        // schedule comes from the department (Schedule mode 0)
  }
  const wsA = XLSX.utils.aoa_to_sheet(A);
  wsA['!merges'] = ['A1:AI1', 'A2:AI2', 'A3:AI3', 'A4:AI4', 'A5:AI5', 'A6:D6', 'E6:AI6', 'A7:A8', 'B7:B8', 'C7:C8', 'D7:D8'].map(r => XLSX.utils.decode_range(r));
  wsA['!cols'] = [{ wch: 12 }, { wch: 12 }, { wch: 12 }, { wch: 8 }, ...Array(NDAYS).fill({ wch: 3.75 })];

  // ---- Sheet 2: Attendance Rules Form
  const B = [['Attendance Rules Form'], ['Company', '', '', ascii(company, 24) || 'cnhs'],
    ['', 'Time1', '', 'Time2', '', 'OT', '', 'Department', '', 'Schedule(1-10 Shifts,Empty/0-Holiday)'],
    ['Shift Number', 'In', 'Out', 'In', 'Out', 'In', 'Out', 'NO.', 'Department', ...DAYS]];
  const rules = { 10: ['Rules'], 12: ['Late Allowance', 0], 13: ['Early Allowance', 0], 14: ['Repeated  Verification(Min)', 3], 15: ['Schedule(0-Department,1-Employee)', 0] };   // left block, rows 11..16
  for (let i = 0; i < 16; i++) {
    const sh = shifts[i] || [], sec = sections.find(s => s.dept_no === i + 1), left = rules[i];
    const row = [i < 10 ? i + 1 : (left ? left[0] : ''), sh[0] || '', sh[1] || '', '', '', '', '', i < 10 ? '' : '', '', '', '', '', '', '', '', ''];
    if (i >= 10) { row.fill('', 0); row[0] = left ? left[0] : ''; if (left && left.length > 1) row[6] = left[1]; }
    else { row[0] = i + 1; row[1] = sh[0] || ''; row[2] = sh[1] || ''; }
    row[7] = i + 1; row[8] = ascii(sec ? sec.name : '', 10) || (i === 15 ? '' : 'Not Set' + (i + 1));
    const wk = deptWeek[i + 1] || Array(7).fill(sec ? 0 : 1);                       // departments nobody uses keep the terminal's default (shift 1)
    for (let d = 0; d < 7; d++) row[9 + d] = wk[d] || (sec ? 0 : 1);
    B.push(row);
  }
  B.push(['Remark:', ...blank(15)],
    ['1. Please modify the attendance information in the white area  strictly according to the format of attendance sheet;', ...blank(15)],
    ['2. Please set a department name based on the actual situation of the company;', ...blank(15)],
    ['3. The passwords of all sheets are listed on this worksheet->upload a password to protect the worksheet;', ...blank(15)]);
  const wsB = XLSX.utils.aoa_to_sheet(B);
  wsB['!merges'] = ['A1:P1', 'A2:C2', 'D2:P2', 'B3:C3', 'D3:E3', 'F3:G3', 'H3:I3', 'J3:P3', 'A15:G16', 'A17:F17', 'A18:F18', 'A19:F19', 'A20:F20', 'A21:P21', 'A22:P22', 'A23:P23', 'A24:P24'].map(r => XLSX.utils.decode_range(r));
  wsB['!cols'] = [...Array(8).fill({ wch: 8.4 }), { wch: 20.7 }, ...Array(7).fill({ wch: 3.75 })];

  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, wsA, 'Employee Form');
  XLSX.utils.book_append_sheet(wb, wsB, 'Attendance Rules Form');
  return { buffer: XLSX.write(wb, { type: 'buffer', bookType: 'biff8' }), shifts };
}
module.exports = { buildEmployeeForm };
