import 'package:dashcn_cli/src/init_action_engine.dart';

class InlineActionJournalEntry {
  final String category;
  final String createdAt;
  final InitExecutionRecord record;

  const InlineActionJournalEntry({
    required this.category,
    required this.createdAt,
    required this.record,
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'createdAt': createdAt,
      'record': record.toJson(),
    };
  }

  factory InlineActionJournalEntry.fromJson(Map<String, dynamic> json) {
    return InlineActionJournalEntry(
      category: json['category']?.toString() ?? 'unknown',
      createdAt: json['createdAt']?.toString() ?? '',
      record: InitExecutionRecord.fromJson(
        (json['record'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, dynamic>{},
      ),
    );
  }
}
