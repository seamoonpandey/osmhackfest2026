import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_config.dart';

class MockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!ApiConfig.useMocks) {
      return handler.next(options);
    }

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final path = options.path;
    final method = options.method;

    // 1. GET /issues (formerly /reports)
    if (path.endsWith('/issues') && method == 'GET') {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _mockIssuesGeoJson,
          statusCode: 200,
        ),
      );
    }

    // 2. GET /roads (formerly /segments)
    if (path.endsWith('/roads') && method == 'GET') {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _mockRoadsGeoJson,
          statusCode: 200,
        ),
      );
    }

    // 3. POST /report (formerly /reports)
    if (path.endsWith('/report') && method == 'POST') {
      try {
        // Handle FormData vs Map
        final data = options.data;
        // In a real FormData, we can't easily inspect fields here in a simple mock 
        // without more logic, but we'll assume it worked.
        // For the mock, we can just log it or add to our volatile list if we want complexity.
        
        // Return expected success response
        return handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'status': 'Issue reported successfully', 
              'photo': 'uploads/mock_photo.jpg'
            },
            statusCode: 200,
          ),
        );
      } catch (e) {
        // Ignore parsing errors for mock
      }
      
      return handler.resolve(
        Response(
          requestOptions: options,
          data: {'status': 'error', 'message': 'Failed to submit'},
          statusCode: 400,
        ),
      );
    }

    handler.next(options);
  }

  // Matches backend: FeatureCollection of issues
  final Map<String, dynamic> _mockIssuesGeoJson = {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [85.3240, 27.7172] // [lon, lat]
        },
        "properties": {
          "id": 1,
          "road_id": 101,
          "type": "pothole",
          "severity": 2, // Corresponds to Severity.level3 in 0-index? Or 1-5 scale? DB uses 1-5.
          "photo": "https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=200&h=200&fit=crop"
        }
      },
      {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [85.3200, 27.7200]
        },
        "properties": {
          "id": 2,
          "road_id": 102,
          "type": "crack",
          "severity": 1,
          "photo": "https://images.unsplash.com/photo-1599395115286-a36c6e737194?w=200&h=200&fit=crop"
        }
      }
    ]
  };

  // Matches backend: FeatureCollection of roads
  final Map<String, dynamic> _mockRoadsGeoJson = {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [85.3240, 27.7120],
            [85.3241, 27.7130],
            [85.3242, 27.7140],
            [85.3243, 27.7150],
            [85.3243, 27.7160],
            [85.3242, 27.7170],
            [85.3241, 27.7180],
            [85.3238, 27.7195]
          ]
        },
        "properties": {
          "id": 101,
          "name": "Durbar Marg",
          "highway": "primary",
          "road_class": "Primary",
          "risk": 75.5, // 0-100
          "severity": 3
        }
      },
      {
        "type": "Feature",
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [85.3200, 27.7185],
            [85.3197, 27.7200],
            [85.3190, 27.7215],
            [85.3180, 27.7230],
            [85.3175, 27.7235]
          ]
        },
        "properties": {
          "id": 102,
          "name": "Lazimpat",
          "highway": "secondary",
          "road_class": "Secondary",
          "risk": 45.0,
          "severity": 1
        }
      }
    ]
  };
}
