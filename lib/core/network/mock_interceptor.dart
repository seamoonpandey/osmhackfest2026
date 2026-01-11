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

  final _mockReportsData = [
    {
      'id': '1',
      'lat': 27.7172,
      'lng': 85.3240,
      'osmNodeId': 'node_123',
      'roadName': 'Durbar Marg',
      'severity': 2, // High
      'description': 'Major pothole on main road.',
      'imageUrl': null,
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
      'imageUrl': null,
      'timestamp': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
    },
  ];

  final _mockSegmentsData = [
    {
      'id': 's1',
      'name': 'Durbar Marg',
      'type': 'primary',
      'priorityScore': 4.5,
      'points': [
        {'lat': 27.7120, 'lng': 85.3240},
        {'lat': 27.7135, 'lng': 85.3241},
        {'lat': 27.7150, 'lng': 85.3242},
        {'lat': 27.7165, 'lng': 85.3243},
        {'lat': 27.7180, 'lng': 85.3241},
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
        {'lat': 27.7195, 'lng': 85.3198},
        {'lat': 27.7205, 'lng': 85.3195},
        {'lat': 27.7215, 'lng': 85.3190},
        {'lat': 27.7225, 'lng': 85.3185},
        {'lat': 27.7235, 'lng': 85.3175},
      ],
    },
  ];
}
