import 'package:flutter/material.dart';

/// Up to 5 subjects, each typed as a code (e.g. MATH7) and a name (e.g. Mathematics 7).
class SubjectsEditor extends StatefulWidget {
  final List<Map<String, String>> initial;
  final ValueChanged<List<Map<String, String>>> onChanged;
  const SubjectsEditor({super.key, this.initial = const [], required this.onChanged});
  @override
  State<SubjectsEditor> createState() => _SubjectsEditorState();
}

class _SubjectsEditorState extends State<SubjectsEditor> {
  static const maxSubjects = 5;
  final rows = <List<TextEditingController>>[];          // [code, name]

  @override
  void initState() {
    super.initState();
    for (final s in widget.initial) { rows.add([TextEditingController(text: s['code']), TextEditingController(text: s['name'])]); }
    if (rows.isEmpty) { rows.add([TextEditingController(), TextEditingController()]); }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }
  @override
  void dispose() { for (final r in rows) { r[0].dispose(); r[1].dispose(); } super.dispose(); }

  void _emit() => widget.onChanged([for (final r in rows) {'code': r[0].text.trim(), 'name': r[1].text.trim()}]);

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < rows.length; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
          SizedBox(width: 108, child: TextField(controller: rows[i][0], textCapitalization: TextCapitalization.characters, onChanged: (_) => _emit(),
              decoration: const InputDecoration(labelText: 'Code', hintText: 'MATH7', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: rows[i][1], textCapitalization: TextCapitalization.words, onChanged: (_) => _emit(),
              decoration: const InputDecoration(labelText: 'Subject name', hintText: 'Mathematics 7', border: OutlineInputBorder(), isDense: true))),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Remove', onPressed: rows.length <= 1 ? null : () { setState(() { final r = rows.removeAt(i); r[0].dispose(); r[1].dispose(); }); _emit(); }),
        ])),
        TextButton.icon(icon: const Icon(Icons.add), label: Text('Add subject (${rows.length}/$maxSubjects)'),
            onPressed: rows.length >= maxSubjects ? null : () { setState(() => rows.add([TextEditingController(), TextEditingController()])); _emit(); }),
      ]);
}
