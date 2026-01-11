import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'network/api_config.dart';
import 'network/mock_interceptor.dart';
import '../models/models.dart';
import 'local_storage.dart';
import 'dart:typed_data';
import 'dart:io'; // Required for File operations

import 'dart:convert';

class ApiClient {
  late final Dio _dio;
  final String _bytezKey = "4964e8ff82c4e31c064f4ee77db4fce4";
  final String _modelId = "keremberke/yolov8m-pothole-segmentation";

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

  Future<Map<String, String?>> analyzePothole(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final response = await _dio.post(
        'https://api.bytez.com/v1/model/run',
        data: {
          'model': _modelId,
          'input': 'data:image/jpeg;base64,$base64Image',
        },
        options: Options(
          headers: {
            'Authorization': _bytezKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.data != null && response.data['output'] != null) {
        final output = response.data['output'];
        String analysis = "Pothole segmentation completed successfully.";
        String? imageUrl;
        
        if (output is String && (output.startsWith('http') || output.startsWith('data:image'))) {
          imageUrl = output;
        } else if (output is List) {
          analysis = "Pothole detected and segmented: ${output.length} areas identified.";
        }
        
        return {
          'analysis': analysis,
          'imageUrl': imageUrl,
        };
      }
    } catch (e) {
      print('AI Analysis error: $e');
    }
    return {};
  }

  Future<void> syncUnsyncedReports() async {
    final unsynced = LocalStorage.getUnsyncedReports();
    for (var report in unsynced) {
      try {
        String? updatedRoadName = report.roadName;
        String? aiAnalysis = report.aiAnalysis;
        String? aiImageUrl = report.aiImageUrl;

        // 1. Background Road Discovery (if was offline)
        if (updatedRoadName == null || updatedRoadName.isEmpty) {
          updatedRoadName = await reverseGeocode(report.lat, report.lng);
        }

        // 2. Background AI Audit (Bytez Segmentation)
        if (aiAnalysis == null && report.imageUrl != null) {
          final result = await analyzePothole(report.imageUrl!);
          aiAnalysis = result['analysis'];
          aiImageUrl = result['imageUrl'];
        }

        // Create updated object
        final updatedReport = RoadReport(
          id: report.id,
          lat: report.lat,
          lng: report.lng,
          osmNodeId: report.osmNodeId,
          roadName: updatedRoadName,
          severity: report.severity,
          description: report.description,
          imageUrl: report.imageUrl,
          timestamp: report.timestamp,
          isSynced: false,
          aiAnalysis: aiAnalysis,
          aiImageUrl: aiImageUrl,
        );

        // Update locally before pushing
        await LocalStorage.saveReport(updatedReport);

        // 3. Push to remote
        await _dio.post('/reports', data: updatedReport.toJson());
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
