import 'package:supabase_flutter/supabase_flutter.dart';

class WorkspaceAccess {
  const WorkspaceAccess({required this.fullName, required this.roles});
  final String fullName;
  final List<Map<String, dynamic>> roles;

  bool get isAdmin => roles.any((r) => r['role'] == 'admin');
  bool get isSupervisor =>
      isAdmin || roles.any((r) => r['role'] == 'supervisor');
  bool get isCompanyWideSupervisor =>
      roles.any((r) => r['role'] == 'supervisor' && r['site_id'] == null);
  bool supervisesAgency(String id) =>
      isAdmin ||
      isCompanyWideSupervisor ||
      roles.any((r) => r['role'] == 'supervisor' && r['agency_id'] == id);
  bool managesAgency(String id) => isAdmin || isCompanyWideSupervisor;
  bool managesSite(Map<String, dynamic> site) =>
      isAdmin ||
      isCompanyWideSupervisor ||
      roles.any(
        (r) =>
            r['role'] == 'supervisor' &&
            r['agency_id'] == site['agency_id'] &&
            (r['site_id'] == null || r['site_id'] == site['id']),
      );
}

Future<PostgrestList> readWorkspaceRows(
  PostgrestTransformBuilder<PostgrestList> query,
) async {
  final rows = <Map<String, dynamic>>[];
  while (true) {
    final response = await query
        .order('id')
        .range(rows.length, rows.length + 199)
        .count(CountOption.exact);
    rows.addAll(response.data);
    if (rows.length >= response.count) return rows;
    if (response.data.isEmpty) {
      throw const FormatException('Incomplete workplace response');
    }
  }
}
