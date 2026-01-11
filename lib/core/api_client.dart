import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'network/api_config.dart';
import 'network/mock_interceptor.dart';
import '../models/models.dart';

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
    try {
      final response = await _dio.get('/reports');
      final List data = response.data;
      return data.map((json) => RoadReport.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> submitReport(RoadReport report) async {
    try {
      await _dio.post('/reports', data: report.toJson());
    } catch (e) {
      rethrow;
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
