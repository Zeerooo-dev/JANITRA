class TaskRecord {
  TaskRecord(this.data) {
    for (final key in [
      'id',
      'user_id',
      'agency_id',
      'site_id',
      'activity_name',
      'scheduled_at',
      'status',
    ]) {
      if (data[key] is! String) throw const FormatException('Invalid task');
    }
    DateTime.parse(data['scheduled_at'] as String);
    if (data['version'] is! int) {
      throw const FormatException('Invalid task version');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get userId => data['user_id'] as String;
  String get agencyId => data['agency_id'] as String;
  String get siteId => data['site_id'] as String;
  String get title => data['activity_name'] as String;
  String get status => data['status'] as String;
  int get version => data['version'] as int;
  bool get verified => data['verified_at'] != null;
  String get submittedAtText => text('submitted_at');
  DateTime get scheduledAt => DateTime.parse(data['scheduled_at'] as String);
  DateTime get deadline => DateTime.parse(data['review_deadline'] as String);
  String get effectiveStatus => data['effective_status'] as String? ?? status;
  String text(String key) => data[key]?.toString() ?? '';
  int get checklistVersion => data['checklist_version'] as int? ?? 0;
  List<Map<String, dynamic>> get checklist =>
      (data['checklist_items'] as List? ?? []).map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        if (row['id'] is! String || row['label'] is! String) {
          throw const FormatException('Invalid checklist');
        }
        return row;
      }).toList();
  Map<String, dynamic> get cachedData => {
    for (final key in [
      'id',
      'user_id',
      'agency_id',
      'site_id',
      'activity_name',
      'location',
      'instructions',
      'checklist_items',
      'checklist_version',
      'checklist_results',
      'agency_name',
      'client_name',
      'site_name',
      'personnel_name',
      'status',
      'version',
      'review_cycle',
      'work_date',
      'scheduled_at',
      'original_deadline',
      'review_deadline',
      'submitted_at',
      'claimed_completed_at',
      'remarks',
      'verified_at',
      'verifier_name',
      'decided_at',
      'decider_name',
      'decision_reason',
      'locked_at',
    ])
      if (data.containsKey(key)) key: data[key],
  };
}

String statusLabel(String status) =>
    const {
      'SCHEDULED': 'Scheduled',
      'PENDING_APPROVAL': 'Pending Approval',
      'APPROVED': 'Approved',
      'REJECTED': 'Rejected',
      'LOCKED_NOT_REVIEWED': 'Locked, not reviewed',
      'REOPENED_FOR_REVIEW': 'Reopened for review',
      'CANCELLED': 'Cancelled',
      'NOT_SUBMITTED': 'Not submitted',
    }[status] ??
    status;

DateTime manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String workDate(DateTime value) {
  final d = value.toUtc().add(const Duration(hours: 8));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String workTime(String? value) {
  if (value == null || value.isEmpty) return '';
  final d = DateTime.parse(value).toUtc().add(const Duration(hours: 8));
  return '${workDate(DateTime.parse(value))} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String dateOnly(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class WorkDraft {
  const WorkDraft({
    required this.task,
    required this.remarks,
    required this.claimedAt,
    required this.requestId,
    this.checklist = const {},
    this.updatedAt,
  });
  final TaskRecord task;
  final String remarks, claimedAt, requestId;
  final Map<String, bool> checklist;
  final String? updatedAt;
  Map<String, dynamic> toJson() => {
    'task': task.cachedData,
    'remarks': remarks,
    'claimed_at': claimedAt,
    'request_id': requestId,
    'checklist_results': checklist,
    'updated_at': updatedAt,
  };
  factory WorkDraft.fromJson(Map<String, dynamic> data) => WorkDraft(
    task: TaskRecord(Map<String, dynamic>.from(data['task'] as Map)),
    remarks: data['remarks'] as String,
    claimedAt: data['claimed_at'] as String,
    requestId: data['request_id'] as String,
    checklist: Map<String, bool>.from(data['checklist_results'] as Map? ?? {}),
    updatedAt: data['updated_at'] as String?,
  );
}
