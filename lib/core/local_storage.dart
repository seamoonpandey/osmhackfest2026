import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

class LocalStorage {
  static const String reportsBoxName = 'road_reports';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(SeverityAdapter());
    Hive.registerAdapter(RoadReportAdapter());
    await Hive.openBox<RoadReport>(reportsBoxName);
  }

  static Box<RoadReport> get reportsBox => Hive.box<RoadReport>(reportsBoxName);

  static Future<void> saveReport(RoadReport report) async {
    await reportsBox.put(report.id, report);
  }

  static List<RoadReport> getAllReports() {
    return reportsBox.values.toList();
  }

  static List<RoadReport> getUnsyncedReports() {
    return reportsBox.values.where((r) => !r.isSynced).toList();
  }

  static Future<void> markAsSynced(String reportId) async {
    final report = reportsBox.get(reportId);
    if (report != null) {
      final syncedReport = RoadReport(
        id: report.id,
        lat: report.lat,
        lng: report.lng,
        osmNodeId: report.osmNodeId,
        roadName: report.roadName,
        severity: report.severity,
        description: report.description,
        imageUrl: report.imageUrl,
        timestamp: report.timestamp,
        isSynced: true,
      );
      await reportsBox.put(reportId, syncedReport);
    }
  }

  static Future<void> clear() async {
    await reportsBox.clear();
  }
}
