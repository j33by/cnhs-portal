const fs = require('fs'), U = '/mnt/user-data/uploads/';
const { parseLogs, parseEmployeeForm, dailyFromPunches } = require('./services/biometric');
const { buildEmployeeForm } = require('./services/xlsWriter');
const p = parseLogs(fs.readFileSync(U + 'Attendance_Logs.txt', 'utf8'));
console.log('punches', p.length, 'ids', [...new Set(p.map(x => x.biometric_id))].join(','));
console.log('daily', dailyFromPunches(p).filter(d => d.date >= '2026-11-12').slice(0, 5));
const people = parseEmployeeForm(fs.readFileSync(U + 'Employee_Form.xls'));
console.log('people', people);
const { buffer, shifts } = buildEmployeeForm({ people, sections: [{ dept_no: 1, name: 'ABM_STUDENTS' }],
  slots: [{ dept_no: 1, day_of_week: 1, start: '07:50', end: '15:00' }, { dept_no: 1, day_of_week: 2, start: '07:50', end: '15:00' }], start: new Date('2026-11-02') });
fs.writeFileSync('/tmp/out.xls', buffer);
console.log('roundtrip', parseEmployeeForm(buffer), shifts);
