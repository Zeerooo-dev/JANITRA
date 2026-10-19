import 'package:uuid/uuid.dart';

List<Map<String, dynamic>> parseChecklist(
  String text, {
  List<dynamic> previous = const [],
}) {
  final labels = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (labels.length > 50 || labels.any((label) => label.length > 200)) {
    throw const FormatException(
      'Use up to 50 checklist items, with at most 200 characters per item.',
    );
  }
  final reusable = <String, List<String>>{};
  for (final item in previous) {
    reusable
        .putIfAbsent(item['label'] as String, () => [])
        .add(item['id'] as String);
  }
  return [
    for (final label in labels)
      {
        'id': reusable[label]?.isNotEmpty == true
            ? reusable[label]!.removeAt(0)
            : const Uuid().v4(),
        'label': label,
      },
  ];
}
