import 'package:dio/dio.dart';
import '../models/models.dart';
import 'package:latlong2/latlong.dart';

class ApiClient {
  final Dio _dio = Dio();

  // Mock data for initial visualization
  final List<RoadReport> _mockReports = [
    RoadReport(
      id: '1',
      location: const LatLng(27.7172, 85.3240),
      severity: Severity.high,
      description: 'Major pothole on main road.',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      roadName: 'Durbar Marg',
    ),
    RoadReport(
      id: '2',
      location: const LatLng(27.7200, 85.3200),
      severity: Severity.medium,
      description: 'Minor cracks appearing.',
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      roadName: 'Lazimpat',
    ),
  ];

  Future<List<RoadReport>> getReports() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));
    return _mockReports;
  }

  Future<void> submitReport(RoadReport report) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    _mockReports.add(report);
    print('Report submitted: ${report.toJson()}');
  }

  Future<List<RoadSegment>> getRoadSegments() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      RoadSegment(
        id: 's1',
        name: 'Durbar Marg',
        type: 'primary',
        priorityScore: 4.5,
        points: [
          const LatLng(27.7150, 85.3240),
          const LatLng(27.7160, 85.3242),
          const LatLng(27.7175, 85.3245),
          const LatLng(27.7190, 85.3240),
        ],
      ),
      RoadSegment(
        id: 's2',
        name: 'Lazimpat',
        type: 'secondary',
        priorityScore: 2.8,
        points: [
          const LatLng(27.7200, 85.3150),
          const LatLng(27.7205, 85.3180),
          const LatLng(27.7200, 85.3210),
          const LatLng(27.7200, 85.3250),
        ],
      ),
    ];
  }
}

final apiClient = ApiClient();
