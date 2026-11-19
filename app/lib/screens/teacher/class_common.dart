import 'package:flutter/material.dart';
import '../../core/teacher_data.dart';
import '../../core/offline.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/calc.dart';

typedef Rows = List<Map<String, dynamic>>;
final ymd = DateFormat('yyyy-MM-dd');
String fmtNum(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Boys first then girls, alphabetical (as in the PHP class lists).
/// The section's students, plus (when a subject is given) students of other sections who enrolled in that subject.
Future<Rows> loadStudents(String sectionId, [String? subjectId]) async {
  final base = await cachedRows('stud|$sectionId', () => sb.from('students').select('id,student_no,first_name,last_name,sex').eq('section_id', sectionId).eq('status', 'enrolled').order('sex', ascending: false).order('last_name').order('first_name'));
  if (subjectId == null) { return base; }
  final ex = await cachedRows('studx|$sectionId|$subjectId', () => sb.from('student_subjects').select('student_id').match({'section_id': sectionId, 'subject_id': subjectId}));
  final have = {for (final b in base) b['id']};
  final ids = [for (final e in ex) if (!have.contains(e['student_id'])) e['student_id'] as String];
  if (ids.isEmpty) { return base; }
  final more = await cachedRows('studm|$sectionId|$subjectId', () => sb.from('students').select('id,student_no,first_name,last_name,sex').inFilter('id', ids).eq('status', 'enrolled'));
  return [...base, ...more]..sort((a, b) {
      final s = '${b['sex']}'.compareTo('${a['sex']}'); if (s != 0) { return s; }
      final l = '${a['last_name']}'.compareTo('${b['last_name']}'); return l != 0 ? l : '${a['first_name']}'.compareTo('${b['first_name']}');
    });
}

Future<int> currentYearId() async => (await cachedRow('year-id', () => sb.from('school_years').select('id').eq('is_current', true).maybeSingle()))!['id'] as int;

/// "Math · Grade 7 Rizal" for sync messages.
String classLabelOf(String sectionId, String subjectId) {
  for (final x in TeacherData.i.classes) { if (x['section_id'] == sectionId && x['subject_id'] == subjectId) { return '${x['subject']} · Grade ${x['grade']} ${x['section']}'; } }
  return 'Class';
}

Widget standingChip(int absences, int free) {
  final s = standingOf(absences, free);
  final col = s == 'dropped' ? Colors.red : s == 'warning' ? Colors.orange : Colors.green;
  return Chip(visualDensity: VisualDensity.compact, label: Text(s == 'ok' ? 'OK' : s == 'warning' ? 'Warning' : 'Over limit', style: const TextStyle(fontSize: 11)), backgroundColor: col.withValues(alpha: .15), side: BorderSide(color: col));
}
