import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api.dart';
import '../core/messenger.dart';
import '../core/offline.dart';
import '../screens/student/student_post_composer.dart';
import '../screens/teacher/post_composer.dart';
import 'ui.dart';
import '../core/img.dart';

const kReactions = {'like': '👍', 'love': '❤️', 'care': '🤗', 'wow': '😮', 'clap': '👏'};
const _cats = {
  'announcement': ['Announcement', Color(0xFF1B5E3B)],
  'reminder': ['Reminder', Color(0xFFB7791F)],
  'activity': ['Activity', Color(0xFF00796B)],
  'assignment': ['Assignment', Color(0xFF3949AB)],
  'urgent': ['Urgent', Color(0xFFC62828)],
  'section': ['Section', Color(0xFF00796B)],
};
Color catColor(String? k) => (_cats[k]?[1] as Color?) ?? const Color(0xFF1B5E3B);
String catLabel(String? k) => (_cats[k]?[0] as String?) ?? 'Announcement';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) { return 'Just now'; }
  if (d.inMinutes < 60) { return '${d.inMinutes}m'; }
  if (d.inHours < 24) { return '${d.inHours}h'; }
  if (d.inDays == 1) { return 'Yesterday'; }
  if (d.inDays < 7) { return DateFormat('EEEE').format(t); }
  return DateFormat(t.year == DateTime.now().year ? 'MMM d' : 'MMM d, y').format(t);
}

/// The class feed. Teachers post (button at the bottom right); everybody sees what was shared with their sections,
/// and can react or comment when the teacher allowed it.
class FeedView extends StatefulWidget {
  final bool canPost;
  /// Student feed: filter chips (All / General / Subject / Section) and posting in the Section filter. [sectionId] = the student's section.
  final bool student; final String? sectionId;
  const FeedView({super.key, this.canPost = false, this.student = false, this.sectionId});
  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  late final Stream<List<Map<String, dynamic>>> _posts = liveStream(widget.student ? 'posts|o|150' : 'posts|o|l', () => sb.from('posts').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(widget.student ? 150 : 60));
  late final Stream<List<Map<String, dynamic>>> _mine = liveStream('post_reactions|user_id=$myUid', () => sb.from('post_reactions').stream(primaryKey: ['post_id', 'user_id']).eq('user_id', myUid));
  final _local = <String, String?>{};            // my reaction, shown at once while the server confirms
  String filter = 'all';                         // student feed: all | general | subject | section

  /// Which filter a post belongs to for THIS student: adviser homeroom posts and classmates' posts = section; subject teachers = subject; everything else = general.
  String _bucket(Map<String, dynamic> p) {
    if (p['section_post_of'] != null) { return 'section'; }
    final k = p['kinds'] is Map ? (p['kinds'] as Map)[widget.sectionId] : null;
    if (k == 'homeroom') { return 'section'; }
    if (k == 'subject') { return 'subject'; }
    return 'general';
  }

  Widget _filters(BuildContext c) {
    const items = [['all', 'All', Icons.dynamic_feed_outlined], ['general', 'General', Icons.campaign_outlined], ['subject', 'Subject teachers', Icons.menu_book_outlined], ['section', 'My section', Icons.groups_outlined]];
    return SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 6), children: [
      for (final it in items) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
        showCheckmark: false, avatar: Icon(it[2] as IconData, size: 18), label: Text(it[1] as String), selected: filter == it[0], onSelected: (_) => setState(() => filter = it[0] as String))),
    ]));
  }

  Widget _sectionComposer(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(borderRadius: BorderRadius.circular(16), onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => const StudentPostComposer())),
        child: Container(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(c).dividerColor.withValues(alpha: .5))),
          child: Row(children: [
            Icon(Icons.edit_outlined, color: cs.primary), const SizedBox(width: 12),
            Expanded(child: Text('Share something with your section…', style: TextStyle(color: Theme.of(c).hintColor, fontSize: 15))),
            Icon(Icons.add_photo_alternate_outlined, color: cs.primary),
          ]))),
      Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Row(children: [
        Icon(Icons.lock_outline, size: 14, color: Theme.of(c).hintColor), const SizedBox(width: 5),
        Expanded(child: Text('Only your classmates and your adviser can see posts here.', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor))),
      ])),
    ]);
  }

  Future<void> _react(String postId, String? kind) async {
    setState(() => _local[postId] = kind);
    try { await Api.put('/api/posts/$postId/reaction', {'kind': kind}); } catch (e) { toastError(e); }
    if (mounted) { setState(() => _local.remove(postId)); }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: widget.canPost ? FloatingActionButton.extended(
          onPressed: () => pushOnce(c, MaterialPageRoute(builder: (_) => const PostComposer())),
          icon: const Icon(Icons.edit_outlined), label: const Text('New post')) : null,
        body: StreamBuilder<List<Map<String, dynamic>>>(stream: _posts, builder: (c, ps) => StreamBuilder<List<Map<String, dynamic>>>(stream: _mine, builder: (c, ms) {
          if (!ps.hasData) { return const Center(child: CircularProgressIndicator()); }
          final mine = {for (final m in ms.data ?? const <Map<String, dynamic>>[]) '${m['post_id']}': '${m['kind']}'};
          final useFilter = widget.student && widget.sectionId != null, inSection = useFilter && filter == 'section';
          final posts = [...ps.data!.where((p) => !useFilter || filter == 'all' || _bucket(p) == filter)]..sort((a, b) {
              if ((a['pinned'] == true) != (b['pinned'] == true)) { return a['pinned'] == true ? -1 : 1; }
              return '${b['created_at']}'.compareTo('${a['created_at']}');
            });
          final head = inSection ? 1 : 0;
          Widget list;
          if (posts.isEmpty && !inSection) {
            list = EmptyState(icon: Icons.dynamic_feed_outlined, title: widget.canPost ? 'Nothing posted yet' : (useFilter && filter != 'all' ? 'No posts here yet' : 'No posts yet'),
                message: widget.canPost ? 'Share an update or photos with your classes.' : 'Posts from your teachers show up here.');
          } else {
            list = Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ListView.separated(
              padding: EdgeInsets.fromLTRB(12, 8, 12, widget.canPost ? 96 : 24), itemCount: posts.length + head + (inSection && posts.isEmpty ? 1 : 0), separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (c, i) {
                if (head == 1 && i == 0) { return _sectionComposer(c); }
                if (posts.isEmpty) { return Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Text('No posts in your section yet.\nBe the first to share something!', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).hintColor)))); }
                final p = posts[i - head], id = '${p['id']}';
                return PostCard(key: ValueKey(id), post: p, moderator: widget.canPost, myReaction: _local.containsKey(id) ? _local[id] : mine[id], onReact: (k) => _react(id, k));
              },
            )));
          }
          if (!useFilter) { return list; }
          return Column(children: [_filters(c), Expanded(child: list)]);
        })),
      );
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post; final String? myReaction; final ValueChanged<String?> onReact;
  /// A teacher who is the adviser can remove a student's section post (the server checks it again).
  final bool moderator;
  const PostCard({super.key, required this.post, required this.myReaction, required this.onReact, this.moderator = false});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool showComments = false, more = false;
  final _reactKey = GlobalKey();

  Map<String, dynamic> get p => widget.post;
  bool get mineAuthor => p['author_id'] == myUid;

  Future<void> _pick() async {
    final box = _reactKey.currentContext?.findRenderObject() as RenderBox?; if (box == null) { return; }
    final o = Overlay.of(context).context.findRenderObject() as RenderBox, pos = box.localToGlobal(Offset.zero, ancestor: o);
    final v = await showMenu<String>(
      context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy - 56, o.size.width - pos.dx - box.size.width, 0), elevation: 6, shape: const StadiumBorder(),
      items: [PopupMenuItem<String>(padding: const EdgeInsets.symmetric(horizontal: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in kReactions.entries) _EmojiButton(emoji: e.value, onTap: () => Navigator.pop(context, e.key)),
      ]))],
    );
    if (v != null) { widget.onReact(v); }
  }

  Future<void> _menu(String v) async {
    try {
      if (v == 'pin') { await Api.patch('/api/posts/${p['id']}', {'pinned': p['pinned'] != true}); }
      else if (v == 'edit') { if (mounted) { await pushOnce(context, MaterialPageRoute(builder: (_) => p['section_post_of'] != null ? StudentPostComposer(existing: p) : PostComposer(existing: p))); } }
      else if (v == 'delete') {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete this post?'), content: const Text('It disappears for everyone, together with its comments and reactions.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
        if (ok == true) { await Api.delete('/api/posts/${p['id']}'); }
      }
    } catch (e) { toastError(e); }
  }

  Widget _header(BuildContext c) {
    final col = catColor(p['category'] as String?), photo = p['author_photo'] as String?, name = '${p['author_name']}';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 21, backgroundImage: photo != null ? CachedNetImage(photo) : null, child: photo == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          if (p['pinned'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.push_pin, size: 15, color: Theme.of(c).colorScheme.primary)),
        ]),
        const SizedBox(height: 1),
        Text('${_ago(DateTime.parse('${p['created_at']}').toLocal())}${p['edited_at'] != null ? ' · edited' : ''}', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
          child: Text(catLabel(p['category'] as String?), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: col))),
      if (mineAuthor || (widget.moderator && p['section_post_of'] != null)) PopupMenuButton<String>(
        padding: EdgeInsets.zero, icon: const Icon(Icons.more_horiz), onSelected: _menu,
        itemBuilder: (_) => mineAuthor
            ? [const PopupMenuItem(value: 'edit', child: Text('Edit')), if (p['section_post_of'] == null) PopupMenuItem(value: 'pin', child: Text(p['pinned'] == true ? 'Unpin' : 'Pin to top')), const PopupMenuItem(value: 'delete', child: Text('Delete'))]
            : [const PopupMenuItem(value: 'delete', child: Text('Delete post'))],
      ),
    ]);
  }

  Widget _body(BuildContext c) {
    final t = '${p['body']}'.trim();
    if (t.isEmpty) { return const SizedBox.shrink(); }
    final long = t.length > 300;
    return Padding(padding: const EdgeInsets.only(top: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(long && !more ? '${t.substring(0, 300).trimRight()}…' : t, style: const TextStyle(fontSize: 15, height: 1.35)),
      if (long) GestureDetector(onTap: () => setState(() => more = !more), child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(more ? 'See less' : 'See more', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)))),
    ]));
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, images = (p['images'] as List?)?.cast<String>() ?? const <String>[];
    final reacts = Map<String, dynamic>.from((p['reactions'] as Map?) ?? const {}), total = (p['reaction_count'] as int?) ?? 0, comments = (p['comment_count'] as int?) ?? 0;
    final top = (reacts.entries.toList()..sort((a, b) => (b.value as int).compareTo(a.value as int))).take(3).map((e) => kReactions[e.key] ?? '').join();
    final allowR = p['allow_reactions'] == true, allowC = p['allow_comments'] == true, mine = widget.myReaction;
    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(c).dividerColor.withValues(alpha: .5))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 8, 0), child: _header(c)),
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 0), child: _body(c)),
        if ('${p['audience'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: Row(children: [
          Icon(Icons.visibility_outlined, size: 14, color: Theme.of(c).hintColor), const SizedBox(width: 5),
          Expanded(child: Text('${p['audience']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor))),
        ])),
        if (images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: PostImages(images)),
        Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: Row(children: [
          if (allowR && total > 0) ...[Text(top, style: const TextStyle(fontSize: 15)), const SizedBox(width: 5), Text('$total', style: TextStyle(fontSize: 13, color: Theme.of(c).hintColor))],
          const Spacer(),
          if (allowC && comments > 0) GestureDetector(onTap: () => setState(() => showComments = !showComments), child: Text('$comments comment${comments == 1 ? '' : 's'}', style: TextStyle(fontSize: 13, color: Theme.of(c).hintColor))),
          if (!allowC) Text('Comments off', style: TextStyle(fontSize: 12, color: Theme.of(c).hintColor)),
        ])),
        if (allowR || allowC) ...[
          const Padding(padding: EdgeInsets.fromLTRB(10, 8, 10, 0), child: Divider(height: 1)),
          Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 2), child: Row(children: [
            if (allowR) Expanded(child: InkWell(
              key: _reactKey, borderRadius: BorderRadius.circular(10), onTap: () => widget.onReact(mine == null ? 'like' : null), onLongPress: _pick,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                mine == null ? Icon(Icons.thumb_up_outlined, size: 19, color: Theme.of(c).hintColor) : Text(kReactions[mine] ?? '👍', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 7),
                Text(mine == null ? 'React' : _name(mine), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: mine == null ? Theme.of(c).hintColor : cs.primary)),
              ])),
            )),
            if (allowC) Expanded(child: InkWell(
              borderRadius: BorderRadius.circular(10), onTap: () => setState(() => showComments = !showComments),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(showComments ? Icons.mode_comment : Icons.mode_comment_outlined, size: 18, color: showComments ? cs.primary : Theme.of(c).hintColor), const SizedBox(width: 7),
                Text(showComments ? 'Hide comments' : 'Comment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: showComments ? cs.primary : Theme.of(c).hintColor)),
              ])),
            )),
          ])),
        ] else const SizedBox(height: 12),
        if (showComments && allowC) CommentsSection(postId: '${p['id']}', postAuthorId: '${p['author_id']}', moderator: widget.moderator && p['section_post_of'] != null),
      ]),
    );
  }

  String _name(String k) => const {'like': 'Like', 'love': 'Love', 'care': 'Care', 'wow': 'Wow', 'clap': 'Clap'}[k] ?? 'Like';
}

class _EmojiButton extends StatelessWidget {
  final String emoji; final VoidCallback onTap;
  const _EmojiButton({required this.emoji, required this.onTap});
  @override
  Widget build(BuildContext c) => InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Text(emoji, style: const TextStyle(fontSize: 27))));
}

/// Comments of one post: loaded only while open, live, newest at the bottom.
class CommentsSection extends StatefulWidget {
  final String postId, postAuthorId; final bool moderator;
  const CommentsSection({super.key, required this.postId, required this.postAuthorId, this.moderator = false});
  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  late final Stream<List<Map<String, dynamic>>> _s = liveStream('post_comments|post_id=${widget.postId}|o', () => sb.from('post_comments').stream(primaryKey: ['id']).eq('post_id', widget.postId).order('created_at', ascending: true));
  final ctl = TextEditingController();
  bool sending = false;
  @override
  void dispose() { ctl.dispose(); super.dispose(); }

  Future<void> _send() async {
    final t = ctl.text.trim(); if (t.isEmpty || sending) { return; }
    setState(() => sending = true);
    try { await Api.post('/api/posts/${widget.postId}/comments', {'text': t}); ctl.clear(); } catch (e) { toastError(e); }
    if (mounted) { setState(() => sending = false); }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    if (m['user_id'] != myUid && widget.postAuthorId != myUid && !widget.moderator) { return; }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete comment?'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
    if (ok == true) { try { await Api.delete('/api/comments/${m['id']}'); } catch (e) { toastError(e); } }
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      color: cs.surfaceContainerLow, padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StreamBuilder<List<Map<String, dynamic>>>(stream: _s, builder: (c, s) {
          if (!s.hasData) { return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))); }
          if (s.data!.isEmpty) { return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Be the first to comment.', style: TextStyle(color: Theme.of(c).hintColor, fontSize: 13))); }
          return Column(children: [for (final m in s.data!) _comment(c, m)]);
        }),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            controller: ctl, minLines: 1, maxLines: 4, maxLength: 500, textCapitalization: TextCapitalization.sentences, onSubmitted: (_) => _send(),
            decoration: InputDecoration(hintText: 'Write a comment…', counterText: '', isDense: true, filled: true, fillColor: cs.surface, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)),
          )),
          const SizedBox(width: 6),
          IconButton.filled(onPressed: sending ? null : _send, icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 18)),
        ]),
      ]),
    );
  }

  Widget _comment(BuildContext c, Map<String, dynamic> m) {
    final photo = m['author_photo'] as String?, name = '${m['author_name']}', role = m['author_role'] == 'teacher' ? 'Teacher' : m['author_role'] == 'parent' ? 'Parent' : '';
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 15, backgroundImage: photo != null ? CachedNetImage(photo) : null, child: photo == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 12)) : null),
      const SizedBox(width: 8),
      Flexible(child: GestureDetector(onLongPress: () => _delete(m), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Theme.of(c).colorScheme.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            if (role.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 6), child: Text(role, style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w600))),
            Padding(padding: const EdgeInsets.only(left: 8), child: Text(_ago(DateTime.parse('${m['created_at']}').toLocal()), style: TextStyle(fontSize: 11, color: Theme.of(c).hintColor))),
          ]),
          const SizedBox(height: 2),
          Text('${m['body']}', style: const TextStyle(fontSize: 14, height: 1.3)),
        ]),
      ))),
    ]));
  }
}

/// 1 to 4+ photos laid out like a feed: one wide, two side by side, three with a big one, four in a grid (+N when there are more).
class PostImages extends StatelessWidget {
  final List<String> urls;
  const PostImages(this.urls, {super.key});

  Widget _img(BuildContext c, int i, {BoxFit fit = BoxFit.cover, int extra = 0}) => GestureDetector(
        onTap: () => pushOnce(c, MaterialPageRoute(builder: (_) => ImageViewer(urls: urls, start: i))),
        child: Stack(fit: StackFit.expand, children: [
          Image(image: CachedNetImage(urls[i]), fit: fit, frameBuilder: (_, child, frame, sync) => frame == null && !sync ? Container(color: Theme.of(c).colorScheme.surfaceContainerHighest) : child, errorBuilder: (_, __, ___) => Container(color: Theme.of(c).colorScheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined))),
          if (extra > 0) Container(color: Colors.black54, alignment: Alignment.center, child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    const gap = 2.0, h = 280.0;
    if (urls.length == 1) { return SizedBox(height: h, width: double.infinity, child: _img(c, 0)); }
    if (urls.length == 2) { return SizedBox(height: 220, child: Row(children: [Expanded(child: _img(c, 0)), const SizedBox(width: gap), Expanded(child: _img(c, 1))])); }
    if (urls.length == 3) {
      return SizedBox(height: h, child: Row(children: [
        Expanded(flex: 3, child: _img(c, 0)), const SizedBox(width: gap),
        Expanded(flex: 2, child: Column(children: [Expanded(child: _img(c, 1)), const SizedBox(height: gap), Expanded(child: _img(c, 2))])),
      ]));
    }
    return SizedBox(height: h, child: Column(children: [
      Expanded(child: Row(children: [Expanded(child: _img(c, 0)), const SizedBox(width: gap), Expanded(child: _img(c, 1))])), const SizedBox(height: gap),
      Expanded(child: Row(children: [Expanded(child: _img(c, 2)), const SizedBox(width: gap), Expanded(child: _img(c, 3, extra: urls.length - 4))])),
    ]));
  }
}

class ImageViewer extends StatefulWidget {
  final List<String> urls; final int start;
  const ImageViewer({super.key, required this.urls, this.start = 0});
  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController pc = PageController(initialPage: widget.start);
  late int i = widget.start;
  @override
  void dispose() { pc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${i + 1} / ${widget.urls.length}', style: const TextStyle(fontSize: 15))),
        body: PageView.builder(
          controller: pc, itemCount: widget.urls.length, onPageChanged: (x) => setState(() => i = x),
          itemBuilder: (_, x) => InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: Image(image: CachedNetImage(widget.urls[x]), fit: BoxFit.contain, frameBuilder: (_, child, frame, sync) => frame == null && !sync ? const CircularProgressIndicator() : child, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white)))),
        ),
      );
}
