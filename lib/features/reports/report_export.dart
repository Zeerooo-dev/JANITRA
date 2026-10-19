import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart' as xl;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import '../work/task_record.dart';

class WorkReport {
  const WorkReport({
    required this.agency,
    required this.period,
    required this.id,
    required this.generatedAt,
    required this.records,
  });
  final String agency, period, id, generatedAt;
  final List<Map<String, dynamic>> records;
  static const columns = {
    'agency_name': 'Manpower Agency',
    'client_name': 'Client Company',
    'site_name': 'Workplace',
    'personnel_name': 'Personnel',
    'work_date': 'Work Date',
    'activity_name': 'Cleaning Activity',
    'location': 'Location',
    'scheduled_at': 'Scheduled (Manila)',
    'claimed_completed_at': 'Claimed Completion (Manila)',
    'submitted_at': 'Official Submission / Employee Confirmation (Manila)',
    'verified_at': 'Supervisor Verification (Manila)',
    'verifier_name': 'Verified By',
    'report_status': 'Final Work Status',
    'decider_name': 'Decision By',
    'decided_at': 'Decision Time (Manila)',
    'decision_reason': 'Decision Reason',
    'remarks': 'Remarks',
    'original_deadline': 'Original Deadline (Manila)',
    'review_deadline': 'Current Deadline (Manila)',
    'locked_at': 'Locked At (Manila)',
    'overrides': 'Override History',
  };
  String cell(Map<String, dynamic> row, String key) {
    if (key == 'report_status') {
      return statusLabel((row[key] ?? row['status']).toString());
    }
    if (key == 'overrides') {
      return (row[key] as List? ?? [])
          .map(
            (o) =>
                '${workTime(o['occurred_at'] as String?)}: ${o['reason']}; new deadline ${workTime(o['new_deadline'] as String?)}',
          )
          .join('\n');
    }
    if ([
      'scheduled_at',
      'claimed_completed_at',
      'submitted_at',
      'verified_at',
      'decided_at',
      'original_deadline',
      'review_deadline',
      'locked_at',
    ].contains(key)) {
      return workTime(row[key] as String?);
    }
    return row[key]?.toString() ?? '';
  }

  Map<String, int> get counts {
    final result = <String, int>{};
    for (final r in records) {
      final status = (r['report_status'] ?? r['status']).toString();
      result[status] = (result[status] ?? 0) + 1;
    }
    return result;
  }

  Future<Uint8List> pdf() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document();
    final navy = PdfColor.fromHex('234E70');
    pw.Widget table(
      List<String> keys,
      List<Map<String, dynamic>> source,
    ) => pw.TableHelper.fromTextArray(
      headers: keys.map((k) => columns[k]!).toList(),
      data: source
          .map(
            (r) => keys.map((k) {
              final value = cell(r, k);
              return ['remarks', 'decision_reason', 'overrides'].contains(k) &&
                      value.length > 200
                  ? 'See detailed notes.'
                  : value;
            }).toList(),
          )
          .toList(),
      columnWidths: {
        for (var i = 0; i < keys.length; i++)
          if (keys[i] == 'work_date') i: const pw.FixedColumnWidth(62),
      },
      headerStyle: pw.TextStyle(
        font: bold,
        color: PdfColors.white,
        fontSize: 9,
      ),
      headerDecoration: pw.BoxDecoration(color: navy),
      cellStyle: pw.TextStyle(font: regular, fontSize: 8.5),
      textStyleBuilder: (index, value, row) => row == 0
          ? null
          : pw.TextStyle(
              font: regular,
              fontSize: 8.5,
              color: value == 'Approved'
                  ? PdfColor.fromHex('006100')
                  : value == 'Rejected'
                  ? PdfColor.fromHex('9C0006')
                  : value.toString().startsWith('Locked')
                  ? PdfColor.fromHex('8A1538')
                  : value == 'Pending Approval'
                  ? PdfColor.fromHex('8A5D00')
                  : PdfColor.fromHex('202C39'),
            ),
      cellPadding: const pw.EdgeInsets.all(5),
      border: pw.TableBorder.all(color: PdfColor.fromHex('D9E2F3'), width: .5),
      cellAlignment: pw.Alignment.topLeft,
    );
    document.addPage(
      pw.MultiPage(
        maxPages: 1000,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (context) => pw.Container(
          color: navy,
          padding: const pw.EdgeInsets.all(12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'JANITRA - Work Report',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 18,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Text(
                  agency,
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '$period | Generated ${workTime(generatedAt)} Manila',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Text(period, style: pw.TextStyle(font: bold, fontSize: 14)),
          pw.Text(
            'Report reference: $id',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Records: ${records.length} | ${counts.entries.map((e) => '${statusLabel(e.key)}: ${e.value}').join(' | ')}',
          ),
          pw.SizedBox(height: 12),
          if (records.isEmpty)
            pw.Text('No authorized work records match this period and filters.')
          else ...[
            table([
              'work_date',
              'personnel_name',
              'activity_name',
              'site_name',
              'scheduled_at',
              'submitted_at',
              'verified_at',
              'report_status',
            ], records),
            pw.SizedBox(height: 18),
            pw.Text(
              'Decisions and remarks',
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            table([
              'work_date',
              'personnel_name',
              'activity_name',
              'verifier_name',
              'decider_name',
              'decided_at',
              'decision_reason',
              'remarks',
            ], records),
            pw.SizedBox(height: 18),
            pw.Text(
              'Timing, agency and lock history',
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            table([
              'agency_name',
              'client_name',
              'personnel_name',
              'activity_name',
              'claimed_completed_at',
              'original_deadline',
              'review_deadline',
              'locked_at',
              'overrides',
            ], records),
            for (final row in records)
              for (final key in ['remarks', 'decision_reason', 'overrides'])
                if (cell(row, key).length > 200) ...[
                  pw.SizedBox(height: 12),
                  pw.Text(
                    '${columns[key]} · ${cell(row, 'personnel_name')} · ${cell(row, 'activity_name')} · ${cell(row, 'work_date')}',
                    style: pw.TextStyle(font: bold, fontSize: 10),
                  ),
                  for (
                    var start = 0;
                    start < cell(row, key).length;
                    start += 400
                  )
                    pw.Text(
                      cell(row, key).substring(
                        start,
                        start + 400 > cell(row, key).length
                            ? cell(row, key).length
                            : start + 400,
                      ),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
          ],
        ],
      ),
    );
    return document.save();
  }

  Uint8List xlsx() {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Summary');
    void write(String name, List<String> headings, List<List<Object>> data) {
      final sheet = excel[name];
      sheet.appendRow(headings.map(xl.TextCellValue.new).toList());
      for (final row in data) {
        sheet.appendRow(
          row
              .map(
                (v) => v is int
                    ? xl.IntCellValue(v)
                    : xl.TextCellValue(v.toString()),
              )
              .toList(),
        );
      }
      final border = xl.Border(
        borderStyle: xl.BorderStyle.Thin,
        borderColorHex: xl.ExcelColor.fromHexString('FFD9E2F3'),
      );
      for (var r = 0; r < sheet.maxRows; r++) {
        for (var c = 0; c < sheet.maxColumns; c++) {
          final cell = sheet.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          );
          final text = cell.value?.toString() ?? '';
          final statusColor = text == 'Approved'
              ? '006100'
              : text == 'Rejected'
              ? '9C0006'
              : text.startsWith('Locked')
              ? '8A1538'
              : text.contains('Pending')
              ? '8A5D00'
              : '202C39';
          cell.cellStyle = xl.CellStyle(
            fontFamily: 'Arial',
            fontSize: 11,
            bold: r == 0,
            fontColorHex: xl.ExcelColor.fromHexString(
              r == 0 ? 'FFFFFFFF' : 'FF$statusColor',
            ),
            backgroundColorHex: xl.ExcelColor.fromHexString(
              r == 0
                  ? 'FF234E70'
                  : r.isEven
                  ? 'FFF5F6F8'
                  : 'FFFFFFFF',
            ),
            textWrapping: xl.TextWrapping.WrapText,
            verticalAlign: xl.VerticalAlign.Top,
            leftBorder: border,
            rightBorder: border,
            topBorder: border,
            bottomBorder: border,
          );
        }
      }
      for (var c = 0; c < headings.length; c++) {
        sheet.setColumnWidth(
          c,
          headings[c].contains('Remarks') || headings[c].contains('History')
              ? 45
              : 24,
        );
      }
    }

    write(
      'Summary',
      ['JANITRA Work Report', 'Value'],
      [
        ['Manpower Agency', agency],
        ['Reporting Period', period],
        ['Generated (Manila)', workTime(generatedAt)],
        ['Report Reference', id],
        ['Total Records', records.length],
        ...counts.entries.map((e) => <Object>[statusLabel(e.key), e.value]),
        [
          'Source',
          'Server-authorized snapshot; claimed completion is separate from official submission.',
        ],
      ],
    );
    void recordsSheet(
      String name,
      List<String> keys,
      Iterable<Map<String, dynamic>> rows,
    ) => write(
      name,
      keys.map((k) => columns[k]!).toList(),
      rows.map((r) => keys.map((k) => cell(r, k)).toList()).toList(),
    );
    recordsSheet('Daily Work Records', columns.keys.toList(), records);
    recordsSheet('Employee Confirmations', [
      'personnel_name',
      'work_date',
      'activity_name',
      'claimed_completed_at',
      'submitted_at',
      'remarks',
    ], records.where((r) => r['submitted_at'] != null));
    recordsSheet('Supervisor Approvals', [
      'personnel_name',
      'work_date',
      'activity_name',
      'verifier_name',
      'verified_at',
      'report_status',
      'decider_name',
      'decided_at',
      'decision_reason',
    ], records.where((r) => r['verified_at'] != null));
    recordsSheet(
      'Pending & Locked Tasks',
      [
        'agency_name',
        'site_name',
        'personnel_name',
        'work_date',
        'activity_name',
        'report_status',
        'original_deadline',
        'review_deadline',
        'locked_at',
        'overrides',
      ],
      records.where(
        (r) => ![
          'APPROVED',
          'REJECTED',
          'CANCELLED',
        ].contains(r['report_status'] ?? r['status']),
      ),
    );
    final encoded = excel.save();
    if (encoded == null) throw StateError('XLSX encoding failed');
    // Apply the standard frozen-header view until the library exposes it in its Dart API.
    final source = ZipDecoder().decodeBytes(encoded), output = Archive();
    for (final file in source) {
      if (file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml')) {
        final document = XmlDocument.parse(
          utf8.decode(file.content as List<int>),
        );
        final root = document.rootElement;
        for (final existing in root.findElements('sheetViews').toList()) {
          existing.parent?.children.remove(existing);
        }
        final views = XmlDocument.parse(
          '<sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
        ).rootElement.copy();
        final before = root.children.indexWhere(
          (e) =>
              e is XmlElement &&
              ['sheetFormatPr', 'cols', 'sheetData'].contains(e.name.local),
        );
        root.children.insert(before < 0 ? 0 : before, views);
        final bytes = utf8.encode(document.toXmlString());
        output.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        output.addFile(file);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(output));
  }
}
