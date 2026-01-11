import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'network/api_config.dart';
import 'network/mock_interceptor.dart';
import '../models/models.dart';
import 'local_storage.dart';
import 'dart:io'; // Required for File operations

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


  Future<int> syncUnsyncedReports() async {
    final unsynced = LocalStorage.getUnsyncedReports();
    int syncedCount = 0;
    
    for (var report in unsynced) {
      try {
        String? updatedRoadName = report.roadName;

        // 1. Background Road Discovery (if was offline)
        if (updatedRoadName == null || updatedRoadName.isEmpty) {
          updatedRoadName = await reverseGeocode(report.lat, report.lng);
        }

        // Create updated object
        final updatedReport = RoadReport(
          id: report.id,
          lat: report.lat,
          lng: report.lng,
          osmNodeId: report.osmNodeId,
          roadName: updatedRoadName,
          severity: report.severity,
          issueType: report.issueType,
          description: report.description,
          imageUrl: report.imageUrl,
          timestamp: report.timestamp,
          isSynced: false,
        );

        // Update locally before pushing
        await LocalStorage.saveReport(updatedReport);

        // 3. Push to remote
        await _dio.post('/reports', data: updatedReport.toJson());
        await LocalStorage.markAsSynced(report.id);
        syncedCount++;
      } catch (e) {
        print('Sync failed for ${report.id}: $e');
      }
    }
    return syncedCount;
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

  Future<List<String>> getNearbyRoads(double lat, double lng) async {
    try {
      final query = '[out:json];way(around:30,$lat,$lng)[highway];out tags;';
      final response = await Dio().get(
        'https://overpass-api.de/api/interpreter',
        queryParameters: {'data': query},
      );
      
      final List elements = response.data['elements'];
      final Set<String> roads = {};
      
      for (var element in elements) {
        final tags = element['tags'];
        if (tags != null && tags['name'] != null) {
          roads.add(tags['name']);
        }
      }
      
      return roads.toList();
    } catch (e) {
      print('Overpass error: $e');
      return [];
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
