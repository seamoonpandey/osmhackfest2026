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

    if (path.endsWith('/reports') && method == 'GET') {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _mockReportsData,
          statusCode: 200,
        ),
      );
    }

    if (path.endsWith('/reports') && method == 'POST') {
      try {
        final data = options.data;
        if (data is Map<String, dynamic>) {
          _mockReportsData.insert(0, data);
        }
      } catch (e) {
        // Ignore parsing errors for mock
      }
      
      return handler.resolve(
        Response(
          requestOptions: options,
          data: {'status': 'success', 'message': 'Report submitted successfully'},
          statusCode: 201,
        ),
      );
    }

    if (path.endsWith('/segments') && method == 'GET') {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _mockSegmentsData,
          statusCode: 200,
        ),
      );
    }

    handler.next(options);
  }

  final List<Map<String, dynamic>> _mockReportsData = [
    {
      'id': '1',
      'lat': 27.7172,
      'lng': 85.3240,
      'osmNodeId': 'node_123',
      'roadName': 'Durbar Marg',
      'severity': 2, // High
      'description': 'Major pothole on main road.',
      'imageUrl': 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=200&h=200&fit=crop',
      'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    },
    {
      'id': '2',
      'lat': 27.7200,
      'lng': 85.3200,
      'osmNodeId': 'node_456',
      'roadName': 'Lazimpat',
      'severity': 1, // Medium
      'description': 'Minor cracks appearing.',
      'imageUrl': 'https://images.unsplash.com/photo-1599395115286-a36c6e737194?w=200&h=200&fit=crop',
      'timestamp': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
    },
  ];

  final List<Map<String, dynamic>> _mockSegmentsData = [
    {
      'id': 's1',
      'name': 'Durbar Marg',
      'type': 'primary',
      'priorityScore': 4.5,
      'points': [
        {'lat': 27.7120, 'lng': 85.3240},
        {'lat': 27.7125, 'lng': 85.32405},
        {'lat': 27.7130, 'lng': 85.3241},
        {'lat': 27.7135, 'lng': 85.32415},
        {'lat': 27.7140, 'lng': 85.3242},
        {'lat': 27.7145, 'lng': 85.32425},
        {'lat': 27.7150, 'lng': 85.3243},
        {'lat': 27.7155, 'lng': 85.32435},
        {'lat': 27.7160, 'lng': 85.3243},
        {'lat': 27.7165, 'lng': 85.32425},
        {'lat': 27.7170, 'lng': 85.3242},
        {'lat': 27.7175, 'lng': 85.32415},
        {'lat': 27.7180, 'lng': 85.3241},
        {'lat': 27.7185, 'lng': 85.3240},
        {'lat': 27.7190, 'lng': 85.3239},
        {'lat': 27.7195, 'lng': 85.3238},
      ],
    },
    {
      'id': 's2',
      'name': 'Lazimpat',
      'type': 'secondary',
      'priorityScore': 2.8,
      'points': [
        {'lat': 27.7185, 'lng': 85.3200},
        {'lat': 27.7190, 'lng': 85.3199},
        {'lat': 27.7195, 'lng': 85.3198},
        {'lat': 27.7200, 'lng': 85.3197},
        {'lat': 27.7205, 'lng': 85.3195},
        {'lat': 27.7210, 'lng': 85.3192},
        {'lat': 27.7215, 'lng': 85.3190},
        {'lat': 27.7220, 'lng': 85.3188},
        {'lat': 27.7225, 'lng': 85.3185},
        {'lat': 27.7230, 'lng': 85.3180},
        {'lat': 27.7235, 'lng': 85.3175},
      ],
    },
  ];
}
