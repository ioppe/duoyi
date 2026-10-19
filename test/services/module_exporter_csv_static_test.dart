import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('ModuleExporter exposes portable CSV exports for core local data', () {
    final exporter = File('lib/services/ics_exporter.dart').readAsStringSync();

    expect(exporter, contains('static String todosCsv('));
    expect(exporter, contains('static String habitsCsv('));
    expect(exporter, contains('static String timeEntriesCsv('));
    expect(exporter, contains('static String notesCsv('));
    expect(exporter, contains('static String diaryCsv('));
    expect(exporter, contains('static String anniversariesCsv('));
    expect(exporter, contains('static String goalsCsv('));

    expect(exporter, contains('duration_minutes'));
    expect(exporter, contains('milestones_done'));
    expect(exporter, contains('next_occurrence'));
    expect(
      exporter,
      contains('title,content,format,pinned,archived,attachments'),
    );
    expect(exporter, contains('n.pinned'));
    expect(exporter, contains('n.archived'));
    expect(exporter, contains('attachments'));
    expect(exporter, contains("s.contains('\\r')"));
    expect(exporter, contains('s.replaceAll(\'"\', \'""\')'));
  });

  test(
    'BackupScreen exposes CSV chips for migration-friendly module export',
    () {
      final screen = File('lib/screens/backup_screen.dart').readAsStringSync();

      expect(screen, contains("title: '单模块导出'"));
      expect(screen, contains("subtitle: 'CSV / Markdown 格式'"));
      expect(screen, contains("待办 · CSV"));
      expect(screen, contains("习惯 · CSV"));
      expect(screen, contains("时间足迹 · CSV"));
      expect(screen, contains("笔记 · CSV"));
      expect(screen, isNot(contains('日记 ·')));
      expect(screen, contains("纪念日 · CSV"));
      expect(screen, contains("目标 · CSV"));

      expect(screen, contains('ModuleExporter.timeEntriesCsv(entries)'));
      expect(screen, contains('ModuleExporter.notesCsv(ns)'));
      expect(screen, isNot(contains('ModuleExporter.diary')));
      expect(screen, contains('ModuleExporter.anniversariesCsv(list)'));
      expect(screen, contains('ModuleExporter.goalsCsv(list)'));
    },
  );
}
