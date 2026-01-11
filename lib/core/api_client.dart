import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'network/api_config.dart';
import 'network/mock_interceptor.dart';
import '../models/models.dart';
import 'local_storage.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ),
    );

    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
    _dio.interceptors.add(MockInterceptor());
  }

  Future<List<RoadReport>> getReports() async {
    // 1. Load local reports first
    final localReports = LocalStorage.getAllReports();
    
    try {
      // 2. Try to get remote reports
      final response = await _dio.get('/reports');
      final List data = response.data;
      final remoteReports = data.map((json) => RoadReport.fromJson(json)).toList();
      
      // 3. Update local storage with remote data (merging)
      for (var remote in remoteReports) {
         // Only save remote if it doesn't exist locally as unsynced
         final local = LocalStorage.reportsBox.get(remote.id);
         if (local == null || local.isSynced) {
           await LocalStorage.saveReport(remote);
         }
      }
      
      // Try to sync any unsynced reports now
      await syncUnsyncedReports();
      
      return LocalStorage.getAllReports();
    } catch (e) {
      // Offline: return whatever we have locally
      return localReports;
    }
  }

  Future<void> submitReport(RoadReport report) async {
    // 1. Always save locally first (Offline First)
    await LocalStorage.saveReport(report);
    
    // 2. Try to push to remote
    try {
      await _dio.post('/reports', data: report.toJson());
      // 3. If successful, mark as synced
      await LocalStorage.markAsSynced(report.id);
    } catch (e) {
      // Fail silently for the UI, it will be synced later
      print('Submission failed, will sync later: $e');
    }
  }

  Future<void> syncUnsyncedReports() async {
    final unsynced = LocalStorage.getUnsyncedReports();
    for (var report in unsynced) {
      try {
        await _dio.post('/reports', data: report.toJson());
        await LocalStorage.markAsSynced(report.id);
      } catch (e) {
        print('Sync failed for ${report.id}: $e');
      }
    }
  }

  Future<List<RoadSegment>> getRoadSegments() async {
    try {
      final response = await _dio.get('/segments');
      final List data = response.data;
      return data.map((json) {
        final List pointsJson = json['points'];
        return RoadSegment(
          id: json['id'],
          name: json['name'],
          type: json['type'],
          priorityScore: json['priorityScore'],
          points: pointsJson.map<LatLng>((p) => LatLng(p['lat'], p['lng'])).toList(),
        );
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await Dio().get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'json',
        },
        options: Options(
          headers: {'User-Agent': 'RoadQualityApp/1.0'},
        ),
      );
      final data = response.data;
      final address = data['address'];
      if (address != null) {
        return address['road'] ?? address['street'] ?? address['suburb'] ?? address['city'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.isEmpty) return [];
    try {
      // We use Nominatim API directly here as it's a public service
      // Note: In a real app, this should probably be proxied through your backend
      final response = await Dio().get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': 1,
          'limit': 5,
        },
        options: Options(
          headers: {'User-Agent': 'RoadQualityApp/1.0'},
        ),
      );
      
      final List data = response.data;
      return data.map((item) => {
        'name': item['display_name'],
        'lat': double.parse(item['lat']),
        'lng': double.parse(item['lon']),
      }).toList();
    } catch (e) {
      return [];
    }
  }
}

final apiClient = ApiClient();
