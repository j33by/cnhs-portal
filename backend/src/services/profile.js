// What each role may change about THEIR OWN profile (Student ID / Teacher ID / device ID can never be edited here).
const bad = m => Object.assign(new Error(m), { status: 400 });
const str = (v, label, { req = false, max = 120 } = {}) => {
  const t = v == null ? '' : String(v).trim();
  if (req && !t) throw bad(`${label} is required`);
  if (t.length > max) throw bad(`${label} is too long`);
  return t || null;
};
const date = (v, label) => {
  if (v == null || v === '') return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(v))) throw bad(`${label} must look like 2010-05-31`);
  const d = new Date(v + 'T00:00:00Z'); if (d > new Date() || d.getUTCFullYear() < 1920) throw bad(`${label} is not a valid date`);
  return v;
};
function cleanProfile(role, b) {
  const f = {}, has = k => Object.prototype.hasOwnProperty.call(b, k);
  if (role === 'student') {
    if (has('first_name')) f.first_name = str(b.first_name, 'First name', { req: true, max: 60 });
    if (has('middle_name')) f.middle_name = str(b.middle_name, 'Middle name', { max: 60 });
    if (has('last_name')) f.last_name = str(b.last_name, 'Last name', { req: true, max: 60 });
    if (has('age')) { const n = Number(b.age); if (!Number.isInteger(n) || n < 4 || n > 99) throw bad('Age must be a whole number from 4 to 99'); f.age = n; }
    if (has('sex')) { if (!['M', 'F'].includes(b.sex)) throw bad('Choose Male or Female'); f.sex = b.sex; }
    if (has('birthdate')) f.birthdate = date(b.birthdate, 'Birthdate');
    if (has('address')) f.address = str(b.address, 'Address', { req: true, max: 200 });
    if (has('lrn')) { const l = str(b.lrn, 'LRN', { max: 20 }); if (l && !/^\d{10,14}$/.test(l)) throw bad('LRN should be 12 digits'); f.lrn = l; }
    if (has('guardian_name')) f.guardian_name = str(b.guardian_name, 'Guardian name', { max: 80 });
    if (has('guardian_contact')) f.guardian_contact = str(b.guardian_contact, 'Guardian contact', { max: 30 });
  } else if (role === 'teacher') {
    if (has('first_name')) f.first_name = str(b.first_name, 'First name', { req: true, max: 60 });
    if (has('last_name')) f.last_name = str(b.last_name, 'Last name', { req: true, max: 60 });
    if (has('birthdate')) f.birthdate = date(b.birthdate, 'Birthdate');
    if (has('address')) f.address = str(b.address, 'Address', { max: 200 });
    if (has('contact_no')) f.contact_no = str(b.contact_no, 'Contact number', { max: 30 });
    if (has('grade_levels')) {
      const g = b.grade_levels;
      if (!Array.isArray(g) || g.length < 1 || g.length > 5 || g.some(x => !Number.isInteger(x) || x < 7 || x > 12) || new Set(g).size !== g.length) throw bad('Choose 1 to 5 grade levels (7 to 12)');
      f.grade_levels = g;
    }
  } else {
    if (has('full_name')) f.full_name = str(b.full_name, 'Name', { req: true, max: 80 });
    if (has('contact_no')) f.contact_no = str(b.contact_no, 'Contact number', { max: 30 });
  }
  return f;
}
module.exports = { cleanProfile };
