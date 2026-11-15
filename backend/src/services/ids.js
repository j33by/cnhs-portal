// Port of the PHP scheme: students 202627-48213, teachers T-70519. Race-safe via SQL function (see 002_ids.sql).
async function nextId(sb, kind, yearLabel) {
  const scope = kind === 'student' ? 'S' + yearLabel.slice(0, 4) + yearLabel.slice(7) : 'T';
  const head = kind === 'student' ? scope.slice(1) + '-' : 'T-';
  const { data, error } = await sb.rpc('next_id_seq', { p_scope: scope });
  if (error) throw error;
  return head + String(data).padStart(5, '0');
}
module.exports = { nextId };
