// Feed: announcements by teachers (text + images), reactions and comments. Visibility = the sections a post is targeted to.
const { notify } = require('../services/notify');
const { parentsOfMany } = require('../services/attendance');

const CATS = ['announcement', 'reminder', 'activity', 'assignment', 'urgent'];
const CAT_LABEL = { announcement: 'Announcement', reminder: 'Reminder', activity: 'Activity', assignment: 'Assignment', urgent: 'Urgent' };
const REACTS = ['like', 'love', 'care', 'wow', 'clap'];

module.exports = function mount(app, { sb, wrap, bad, teacherOnly, curYear }) {
  const BUCKET_URL = `${process.env.SUPABASE_URL}/storage/v1/object/public/pictures/`;
  const chunk = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };

  // Sections this person belongs to (same rule as the database function my_section_ids)
  const mySections = async q => {
    const uid = q.user.id, role = q.profile?.role, out = new Set();
    if (role === 'student') { const { data } = await sb.from('students').select('section_id').eq('id', uid).maybeSingle(); if (data?.section_id) out.add(data.section_id); }
    else if (role === 'parent') {
      const { data: l } = await sb.from('parent_links').select('student_id').eq('parent_id', uid).eq('status', 'approved');
      const ids = (l || []).map(x => x.student_id);
      if (ids.length) for (const s of (await sb.from('students').select('section_id').in('id', ids)).data || []) if (s.section_id) out.add(s.section_id);
    } else if (role === 'teacher') {
      for (const s of (await sb.from('section_subjects').select('section_id').eq('teacher_id', uid)).data || []) out.add(s.section_id);
      for (const s of (await sb.from('sections').select('id').eq('adviser_id', uid)).data || []) out.add(s.id);
    }
    return out;
  };
  const loadPost = async (q, id) => {
    const { data: p } = await sb.from('posts').select('*').eq('id', id).maybeSingle(); if (!p) throw bad('Post not found', 404);
    if (p.author_id !== q.user.id) {
      const mine = await mySections(q), { data: t } = await sb.from('post_targets').select('section_id').eq('post_id', id);
      if (!(t || []).some(x => mine.has(x.section_id))) throw bad('Post not found', 404);
    }
    return p;
  };
  const pathOf = url => url.startsWith(BUCKET_URL) ? url.slice(BUCKET_URL.length) : null;
  const removeImages = async urls => { const paths = (urls || []).map(pathOf).filter(Boolean); if (paths.length) await sb.storage.from('pictures').remove(paths).catch(() => {}); };
  const snippet = (t, n = 110) => { const s = String(t || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; };

  // ---- Create a post. targets: [{kind:'section',section_id} | {kind:'subject',section_id,subject_id} | {kind:'homeroom',section_id} | {kind:'grade',grade_level}]
  app.post('/api/posts', teacherOnly, wrap(async (q, r) => {
    const b = q.body || {}, uid = q.user.id, text = String(b.text || '').trim().slice(0, 3000);
    const images = Array.isArray(b.images) ? b.images.slice(0, 6) : [];
    if (!text && !images.length) throw bad('Write something or add a photo.');
    if (images.some(u => typeof u !== 'string' || !u.startsWith(BUCKET_URL + uid + '/'))) throw bad('Invalid image.');
    const category = CATS.includes(b.category) ? b.category : 'announcement';
    const tg = Array.isArray(b.targets) ? b.targets : []; if (!tg.length) throw bad('Choose who can see this post.'); if (tg.length > 80) throw bad('Too many audiences.');

    const [{ data: taught }, { data: advised }, { data: me }, yr] = await Promise.all([
      sb.from('section_subjects').select('section_id,subject_id,sections(grade_level,name),subjects(name)').eq('teacher_id', uid),
      sb.from('sections').select('id,grade_level,name').eq('adviser_id', uid),
      sb.from('teachers').select('grade_levels').eq('id', uid).maybeSingle(), curYear()]);
    const secInfo = new Map(), grades = new Set(me?.grade_levels || []);
    for (const t of taught || []) { secInfo.set(t.section_id, { grade: t.sections.grade_level, name: t.sections.name }); grades.add(t.sections.grade_level); }
    for (const a of advised || []) { secInfo.set(a.id, { grade: a.grade_level, name: a.name }); grades.add(a.grade_level); }
    const subjOf = new Map((taught || []).map(t => [t.section_id + '|' + t.subject_id, t.subjects?.name]));
    const advSet = new Set((advised || []).map(a => a.id));

    const rows = new Map(), labels = [];                 // section_id -> kind (the most specific one wins)
    const rank = { grade: 0, section: 1, subject: 2, homeroom: 3 };
    const put = (sid, kind) => { if (!rows.has(sid) || rank[kind] > rank[rows.get(sid)]) rows.set(sid, kind); };
    for (const t of tg) {
      if (t.kind === 'grade') {
        const g = +t.grade_level; if (!grades.has(g)) throw bad(`You do not handle Grade ${g}.`, 403);
        const { data: secs } = await sb.from('sections').select('id').eq('school_year_id', yr.id).eq('grade_level', g);
        for (const s of secs || []) put(s.id, 'grade'); labels.push(`Grade ${g} (all sections)`);
      } else if (t.kind === 'section') {
        const i = secInfo.get(t.section_id); if (!i) throw bad('You do not teach that section.', 403);
        put(t.section_id, 'section'); labels.push(`Grade ${i.grade} · ${i.name}`);
      } else if (t.kind === 'subject') {
        const sn = subjOf.get(t.section_id + '|' + t.subject_id), i = secInfo.get(t.section_id); if (!sn || !i) throw bad('You do not teach that class.', 403);
        put(t.section_id, 'subject'); labels.push(`Grade ${i.grade} · ${i.name} · ${sn}`);
      } else if (t.kind === 'homeroom') {
        if (!advSet.has(t.section_id)) throw bad('Only the adviser can post to a homeroom.', 403);
        const i = secInfo.get(t.section_id); put(t.section_id, 'homeroom'); labels.push(`Homeroom · Grade ${i.grade} ${i.name}`);
      } else throw bad('Unknown audience.');
    }
    if (!rows.size) throw bad('No students are in that audience yet.');
    const audience = labels.length > 3 ? labels.slice(0, 2).join(' + ') + ` + ${labels.length - 2} more` : labels.join(' + ');
    const name = q.profile.full_name || 'Teacher';
    const { data: post, error } = await sb.from('posts').insert({ author_id: uid, author_name: name, author_photo: q.profile.photo_url || null, body: text, category, images,
      allow_reactions: b.allow_reactions !== false, allow_comments: b.allow_comments !== false, pinned: !!b.pinned, audience }).select().single();
    if (error) throw error;
    const { error: e2 } = await sb.from('post_targets').insert([...rows].map(([section_id, kind]) => ({ post_id: post.id, section_id, kind })));
    if (e2) { await sb.from('posts').delete().eq('id', post.id); throw e2; }

    let notified = 0;
    if (b.notify !== false) {                            // students + parents of every audience section get an alert
      const { data: studs } = await sb.from('students').select('id').in('section_id', [...rows.keys()]).eq('status', 'enrolled');
      const ids = (studs || []).map(s => s.id), parents = await parentsOfMany(sb, ids), all = new Set(ids);
      for (const p of parents.values()) for (const x of p) all.add(x);
      const title = `${name} · ${CAT_LABEL[category]}`, body = text ? snippet(text) : 'Shared a photo';
      for (const part of chunk([...all], 400)) { await notify(sb, part, { kind: 'feed', title, body, data: { post_id: post.id } }); notified += part.length; }
    }
    r.json({ id: post.id, sections: rows.size, notified });
  }));

  app.patch('/api/posts/:id', teacherOnly, wrap(async (q, r) => {
    const p = await loadPost(q, q.params.id); if (p.author_id !== q.user.id) throw bad('Only the author can edit this post.', 403);
    const b = q.body || {}, upd = {};
    if (b.text !== undefined) { upd.body = String(b.text).trim().slice(0, 3000); if (upd.body !== p.body) upd.edited_at = new Date().toISOString(); }
    if (CATS.includes(b.category)) upd.category = b.category;
    for (const k of ['allow_reactions', 'allow_comments', 'pinned']) if (typeof b[k] === 'boolean') upd[k] = b[k];
    if (Array.isArray(b.images)) { const keep = b.images.filter(u => p.images.includes(u)); await removeImages(p.images.filter(u => !keep.includes(u))); upd.images = keep; }
    if (!(upd.body ?? p.body).trim() && !(upd.images ?? p.images).length) throw bad('A post needs text or a photo.');
    const { error } = await sb.from('posts').update(upd).eq('id', p.id); if (error) throw error; r.json({ ok: true });
  }));
  app.delete('/api/posts/:id', teacherOnly, wrap(async (q, r) => {
    const p = await loadPost(q, q.params.id); if (p.author_id !== q.user.id) throw bad('Only the author can delete this post.', 403);
    await sb.from('posts').delete().eq('id', p.id); await removeImages(p.images); r.json({ ok: true });
  }));

  // ---- Reactions: one per person, tap again (kind null) to remove
  app.put('/api/posts/:id/reaction', wrap(async (q, r) => {
    const p = await loadPost(q, q.params.id); if (!p.allow_reactions) throw bad('Reactions are turned off for this post.', 403);
    const kind = q.body?.kind;
    if (kind == null) await sb.from('post_reactions').delete().match({ post_id: p.id, user_id: q.user.id });
    else { if (!REACTS.includes(kind)) throw bad('Unknown reaction.'); const { error } = await sb.from('post_reactions').upsert({ post_id: p.id, user_id: q.user.id, kind }, { onConflict: 'post_id,user_id' }); if (error) throw error; }
    const { data: all } = await sb.from('post_reactions').select('kind').eq('post_id', p.id), sum = {};
    for (const x of all || []) sum[x.kind] = (sum[x.kind] || 0) + 1;
    await sb.from('posts').update({ reactions: sum, reaction_count: (all || []).length }).eq('id', p.id);
    r.json({ reactions: sum, count: (all || []).length });
  }));

  // ---- Comments
  const recount = async id => { const { count } = await sb.from('post_comments').select('id', { count: 'exact', head: true }).eq('post_id', id); await sb.from('posts').update({ comment_count: count || 0 }).eq('id', id); return count || 0; };
  app.post('/api/posts/:id/comments', wrap(async (q, r) => {
    const p = await loadPost(q, q.params.id); if (!p.allow_comments) throw bad('Comments are turned off for this post.', 403);
    const text = String(q.body?.text || '').trim().slice(0, 500); if (!text) throw bad('Write a comment first.');
    const { data: c, error } = await sb.from('post_comments').insert({ post_id: p.id, user_id: q.user.id, author_name: q.profile.full_name || 'User', author_photo: q.profile.photo_url || null, author_role: q.profile.role, body: text }).select().single();
    if (error) throw error;
    const count = await recount(p.id);
    if (p.author_id !== q.user.id) await notify(sb, [p.author_id], { kind: 'feed', title: `${c.author_name} commented on your post`, body: snippet(text), data: { post_id: p.id } });
    r.json({ id: c.id, count });
  }));
  app.delete('/api/comments/:id', wrap(async (q, r) => {
    const { data: c } = await sb.from('post_comments').select('id,post_id,user_id').eq('id', q.params.id).maybeSingle(); if (!c) throw bad('Comment not found', 404);
    const { data: p } = await sb.from('posts').select('author_id').eq('id', c.post_id).maybeSingle();
    if (c.user_id !== q.user.id && p?.author_id !== q.user.id) throw bad('You can only delete your own comments.', 403);
    await sb.from('post_comments').delete().eq('id', c.id); r.json({ count: await recount(c.post_id) });
  }));
};
