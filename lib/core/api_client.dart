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
      // 2. Try to get remote reports (now /issues)
      final response = await _dio.get('/issues');
      final Map<String, dynamic> featureCollection = response.data;
      final List features = featureCollection['features'];
      
      final remoteReports = features.map((feature) {
        final props = feature['properties'];
        final geometry = feature['geometry'];
        final coords = geometry['coordinates']; // [lon, lat]
        
        final severityInt = (props['severity'] as num?)?.toInt() ?? 1;
        // Ensure within valid range 1-5, convert to 0-4 index
        final severityIndex = (severityInt - 1).clamp(0, Severity.values.length - 1);
        
        return RoadReport(
          id: props['id'].toString(),
          lat: (coords[1] as num).toDouble(),
          lng: (coords[0] as num).toDouble(),
          osmNodeId: null, // New API doesn't return this
          roadName: 'Road #${props['road_id']}', // Placeholder as API only gives road_id
          severity: Severity.values[severityIndex],
          issueType: props['type'],
          description: '${props['type']} reported', // Default description
          imageUrl: props['photo'],
          timestamp: DateTime.now(), // API doesn't return timestamp, verify if needed
          isSynced: true,
        );
      }).toList();
      
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
      print('Error fetching reports: $e');
      // Offline: return whatever we have locally
      return localReports;
    }
  }

  Future<void> submitReport(RoadReport report) async {
    // 1. Always save locally first (Offline First)
    await LocalStorage.saveReport(report);
    
    // 2. Try to push to remote
    try {
      // dynamically find the nearest road ID from our available segments
      final roadId = await _findNearestRoadId(report.lat, report.lng);
      
      final formData = FormData.fromMap({
        'road_id': roadId,
        'issue_type': report.issueType ?? 'other',
        'severity': report.severity.index + 1, // 1-based
        'lat': report.lat, 
        'lon': report.lng, 
      });
      
      // If report.imageUrl is a local file path (which it should be for new report)
      if (report.imageUrl != null && !report.imageUrl!.startsWith('http')) {
        formData.files.add(MapEntry(
          'photo',
          await MultipartFile.fromFile(report.imageUrl!),
        ));
      }

      await _dio.post('/report', data: formData);
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
        final roadId = await _findNearestRoadId(report.lat, report.lng);
        
        final formData = FormData.fromMap({
          'road_id': roadId,
          'issue_type': report.issueType ?? 'other',
          'severity': report.severity.index + 1,
          'lat': report.lat,
          'lon': report.lng,
        });

        if (report.imageUrl != null && !report.imageUrl!.startsWith('http')) {
             formData.files.add(MapEntry(
               'photo',
               await MultipartFile.fromFile(report.imageUrl!),
             ));
        }

        // 3. Push to remote
        await _dio.post('/report', data: formData);
        await LocalStorage.markAsSynced(report.id);
        syncedCount++;
      } catch (e) {
        print('Sync failed for ${report.id}: $e');
      }
    }
    return syncedCount;
  }
  
  // Helper to find nearest road ID based on location
  Future<int> _findNearestRoadId(double lat, double lng) async {
    try {
      // Reuse getRoadSegments which now fetches from the new API structure
      final segments = await getRoadSegments();
      
      String? nearestId;
      double minDistance = double.infinity;
      const distance = Distance();
      final target = LatLng(lat, lng);
      
      for (var segment in segments) {
        for (var point in segment.points) {
           final d = distance.as(LengthUnit.Meter, target, point);
           if (d < minDistance) {
             minDistance = d;
             nearestId = segment.id;
           }
        }
      }
      
      // If no road found within reasonable distance (e.g. 50m), user might be off-road
      // But for now we just return the nearest one.
      return int.tryParse(nearestId ?? '0') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<List<RoadSegment>> getRoadSegments() async {
    try {
      final response = await _dio.get('/roads');
      final Map<String, dynamic> featureCollection = response.data;
      final List features = featureCollection['features'];
      
      return features.map((feature) {
        final props = feature['properties'];
        final geometry = feature['geometry'];
        final List coordinates = geometry['coordinates']; // List of [lon, lat]
        
        final points = coordinates.map<LatLng>((p) {
          // GeoJSON is [lon, lat]
          return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
        }).toList();

        final risk = (props['risk'] as num?)?.toDouble() ?? 0.0;

        return RoadSegment(
          id: props['id'].toString(),
          name: props['name'] ?? 'Unnamed Road',
          type: props['highway'] ?? props['road_class'] ?? 'unknown',
          priorityScore: risk / 20.0, // Risk 0-100 -> 0-5
          points: points,
        );
      }).toList();
    } catch (e) {
      print('Error fetching segments: $e');
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
