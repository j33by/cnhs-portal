// Rebuilds Employee_Form.xls (same two sheets the terminal reads) from the database.
const XLSX = require('xlsx');
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const NDAYS = 38;                                  // columns in the original template (42 - 4)

// people: [{biometric_id,name,dept_no}]  sections: [{dept_no,name}]  slots: [{dept_no,day_of_week,start,end}]
function buildEmployeeForm({ people, sections, slots, company = 'Calape National High School', start = new Date() }) {
  // One "school day" shift per distinct first-start/last-end span (device allows max 10)
  const span = new Map();                          // dept|day -> [min,max]
  for (const s of slots) { const k = s.dept_no + '|' + s.day_of_week, v = span.get(k);
    span.set(k, v ? [v[0] < s.start ? v[0] : s.start, v[1] > s.end ? v[1] : s.end] : [s.start, s.end]); }
  const shifts = []; const shiftOf = ([a, b]) => { let i = shifts.findIndex(x => x[0] === a && x[1] === b);
    if (i < 0) { if (shifts.length >= 10) return 0; shifts.push([a, b]); i = shifts.length - 1; } return i + 1; };
  const deptWeek = {}; for (const [k, v] of span) { const [d, w] = k.split('|'); (deptWeek[d] ||= Array(7).fill(0))[+w] = shiftOf(v); }

  const iso = d => d.toISOString().slice(0, 10);
  const A = [['Employee Form'], ['Remark:'],
    ['1.Upload employee information, please fill in the information under the * column;'],
    ['2.Edit employee scheduling upload:1-10 Shifts,25-Leave,26-Business trips,Empty/0-Holidays;'],
    ['3.Authority:0-Employee, 1-Admin;'],
    ['Date(Example:2000-01-01)', '', '', '', iso(start)]];
  const days = [...Array(NDAYS)].map((_, i) => new Date(start.getTime() + i * 864e5));
  A.push(['*ID', '*Name', '*Department(1-16)', '*Authority', ...days.map(d => d.getUTCDate())]);
  A.push(['', '', '', '', ...days.map(d => DAYS[d.getUTCDay()])]);
  for (const p of people) A.push([p.biometric_id, p.name, p.dept_no || 1, 0,
    ...days.map(d => (p.dept_no && deptWeek[p.dept_no] ? deptWeek[p.dept_no][d.getUTCDay()] : 0) || '')]);

  const B = [['Attendance Rules Form'], ['Company', '', '', company],
    ['', 'Time1', '', 'Time2', '', 'OT', '', 'Department', '', 'Schedule(1-10 Shifts,Empty/0-Holiday)'],
    ['Shift Number', 'In', 'Out', 'In', 'Out', 'In', 'Out', 'NO.', 'Department', ...DAYS]];
  for (let i = 0; i < 16; i++) {
    const sh = shifts[i] || [], sec = sections.find(s => s.dept_no === i + 1);
    B.push([i < 10 ? i + 1 : '', sh[0] || '', sh[1] || '', '', '', '', '', i + 1, sec ? sec.name : '',
      ...(deptWeek[i + 1] || Array(7).fill(0))]);
  }
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(A), 'Employee Form');
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(B), 'Attendance Rules Form');
  return { buffer: XLSX.write(wb, { type: 'buffer', bookType: 'biff8' }), shifts };
}
module.exports = { buildEmployeeForm };
