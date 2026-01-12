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

    _dio.interceptors.add(
      LogInterceptor(responseBody: true, requestBody: true),
    );
    _dio.interceptors.add(MockInterceptor());
  }

  Future<List<RoadReport>> getReports() async {
    // 1. Load local reports first
    final localReports = LocalStorage.getAllReports();

    try {
      // 2. Try to get remote reports from current backend
      final response = await _dio.get('/issues');
      final Map<String, dynamic> featureCollection = response.data;
      final List features = featureCollection['features'];
      print('DEBUG: Fetched ${features.length} issues from backend');

      final remoteReports = await Future.wait(
        features.map((feature) async {
          final props = feature['properties'];
          final geometry = feature['geometry'];
          final coords = geometry['coordinates']; // [lon, lat]
          final lat = (coords[1] as num).toDouble();
          final lng = (coords[0] as num).toDouble();

          final severityInt = (props['severity'] as num?)?.toInt() ?? 1;
          print('DEBUG: Issue ${props['id']} has severity $severityInt');
          final severityIndex = (severityInt - 1).clamp(
            0,
            Severity.values.length - 1,
          );

          // Resolve Road Name
          String? roadName;
          final roadId = props['road_id'].toString();

          // 1. Try Cache
          if (_cachedSegments != null) {
            try {
              final segment = _cachedSegments!.firstWhere(
                (s) => s.id == roadId,
              );
              roadName = segment.name;
            } catch (_) {}
          }

          // 2. Fallback to Reverse Geocode if cache missed or name is generic
          if (roadName == null || roadName.isEmpty) {
            roadName = await reverseGeocode(lat, lng);
          }

          // 3. Fallback to ID
          roadName ??= 'Road #$roadId';

          return RoadReport(
            id: props['id'].toString(),
            lat: lat,
            lng: lng,
            osmNodeId: null,
            roadName: roadName,
            severity: Severity.values[severityIndex],
            issueType: props['type'],
            description: '${props['type']} reported',
            imageUrl:
                props['photo'] != null && !props['photo'].startsWith('http')
                ? '${ApiConfig.baseUrl}${props['photo']}'
                : props['photo'],
            timestamp: DateTime.now(),
            isSynced: true,
          );
        }),
      );

      // 3. Clear old synced reports and replace with fresh remote data
      // Keep only unsynced local reports (user's pending submissions)
      final unsyncedReports = LocalStorage.getUnsyncedReports();
      await LocalStorage.clear();

      // Restore unsynced reports first
      for (var unsynced in unsyncedReports) {
        await LocalStorage.saveReport(unsynced);
      }

      // Save fresh remote reports
      for (var remote in remoteReports) {
        // Only save if not already in unsynced (avoid duplicates)
        final exists = unsyncedReports.any((u) => u.id == remote.id);
        if (!exists) {
          await LocalStorage.saveReport(remote);
        }
      }

      // Try to sync any unsynced reports now (pushing local to remote)
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
        formData.files.add(
          MapEntry('photo', await MultipartFile.fromFile(report.imageUrl!)),
        );
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
          formData.files.add(
            MapEntry('photo', await MultipartFile.fromFile(report.imageUrl!)),
          );
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
  // Optimized: Uses bounding box filtering to avoid checking all points
  Future<int> _findNearestRoadId(double lat, double lng) async {
    try {
      final segments = await getRoadSegments();
      if (segments.isEmpty) return 0;

      String? nearestId;
      double minDistance = double.infinity;
      const distance = Distance();
      final target = LatLng(lat, lng);

      // ~100 meters in degrees (rough approximation)
      const searchRadius = 0.001;

      // First pass: only check segments whose bounding box is near the target
      final nearbySegments = segments
          .where(
            (s) => s.isNearBoundingBox(lat, lng, paddingDegrees: searchRadius),
          )
          .toList();

      // If no nearby segments, expand search to all (fallback)
      final segmentsToCheck = nearbySegments.isNotEmpty
          ? nearbySegments
          : segments;

      for (var segment in segmentsToCheck) {
        // Only sample a few points instead of all - first, last, and middle
        final points = segment.points;
        final sampleIndices = <int>[
          0,
          if (points.length > 2) points.length ~/ 2,
          if (points.length > 1) points.length - 1,
        ];

        for (var i in sampleIndices) {
          final d = distance.as(LengthUnit.Meter, target, points[i]);
          if (d < minDistance) {
            minDistance = d;
            nearestId = segment.id;
          }
        }
      }

      return int.tryParse(nearestId ?? '0') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  List<RoadSegment>? _cachedSegments;

  Future<List<RoadSegment>> getRoadSegments({bool forceRefresh = false}) async {
    // Clear cache on refresh to ensure fresh data
    if (forceRefresh) {
      _cachedSegments = null;
    }

    if (_cachedSegments != null && _cachedSegments!.isNotEmpty) {
      return _cachedSegments!;
    }

    try {
      final response = await _dio.get('/roads');
      final Map<String, dynamic> featureCollection = response.data;
      final List features = featureCollection['features'];

      _cachedSegments = features.expand<RoadSegment>((feature) {
        final props = feature['properties'];
        final geometry = feature['geometry'];
        if (geometry == null) return <RoadSegment>[];

        final type = geometry['type'];
        final List<List<LatLng>> paths = [];

        if (type == 'LineString') {
          final List coords = geometry['coordinates'];
          paths.add(
            coords
                .map<LatLng>(
                  (p) => LatLng(
                    (p[1] as num).toDouble(),
                    (p[0] as num).toDouble(),
                  ),
                )
                .toList(),
          );
        } else if (type == 'MultiLineString') {
          final List lines = geometry['coordinates'];
          for (var line in lines) {
            final List coords = line;
            paths.add(
              coords
                  .map<LatLng>(
                    (p) => LatLng(
                      (p[1] as num).toDouble(),
                      (p[0] as num).toDouble(),
                    ),
                  )
                  .toList(),
            );
          }
        }

        final risk = (props['risk'] as num?)?.toDouble() ?? 0.0;
        final id = props['id'].toString();
        final name = props['name'] ?? 'Unnamed Road';
        final roadType = props['highway'] ?? props['road_class'] ?? 'unknown';
        final priority = risk / 20.0; // Risk 0-100 -> 0-5

        return paths.map(
          (points) => RoadSegment(
            id: id, // Multiple segments can share the same ID if they are part of a MultiLineString
            name: name,
            type: roadType,
            priorityScore: priority,
            points: points,
          ),
        );
      }).toList();

      return _cachedSegments!;
    } catch (e) {
      print('Error fetching segments: $e');
      // Return empty list instead of rethrowing to allow map to load at least reports
      return _cachedSegments ?? [];
    }
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await Dio().get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {'lat': lat, 'lon': lng, 'format': 'json'},
        options: Options(headers: {'User-Agent': 'RoadQualityApp/1.0'}),
      );
      final data = response.data;
      final address = data['address'];
      if (address != null) {
        return address['road'] ??
            address['street'] ??
            address['suburb'] ??
            address['city'];
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
        options: Options(headers: {'User-Agent': 'RoadQualityApp/1.0'}),
      );

      final List data = response.data;
      return data
          .map(
            (item) => {
              'name': item['display_name'],
              'lat': double.parse(item['lat']),
              'lng': double.parse(item['lon']),
            },
          )
          .toList();
    } catch (e) {
      return [];
    }
  }
}

final apiClient = ApiClient();
