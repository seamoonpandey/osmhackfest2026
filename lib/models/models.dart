import 'package:latlong2/latlong.dart';
import 'package:hive/hive.dart';

part 'models.g.dart';

@HiveType(typeId: 0)
enum Severity { 
  @HiveField(0) level1, // Low
  @HiveField(1) level2, // Medium
  @HiveField(2) level3, // High
  @HiveField(3) level4, // Very High
  @HiveField(4) level5  // Critical
}

@HiveType(typeId: 1)
class RoadReport {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final double lat;
  @HiveField(2)
  final double lng;
  @HiveField(3)
  final String? osmNodeId;
  @HiveField(4)
  final String? roadName;
  @HiveField(5)
  final Severity severity;
  @HiveField(6)
  final String description;
  @HiveField(7)
  final String? imageUrl;
  @HiveField(8)
  final DateTime timestamp;
  @HiveField(9)
  final bool isSynced;
  @HiveField(10)
  final String? issueType;


  RoadReport({
    required this.id,
    double? lat,
    double? lng,
    LatLng? location,
    this.osmNodeId,
    this.roadName,
    required this.severity,
    this.issueType = 'Other',
    required this.description,
    this.imageUrl,
    required this.timestamp,
    this.isSynced = false,
  })  : this.lat = lat ?? location?.latitude ?? 0.0,
        this.lng = lng ?? location?.longitude ?? 0.0;

  LatLng get location => LatLng(lat, lng);

  String get displayName {
    if (roadName != null && roadName!.isNotEmpty) return roadName!;
    if (description.isNotEmpty) {
      return description.length > 20 ? '${description.substring(0, 17)}...' : description;
    }
    return 'Unnamed Location';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': location.latitude,
      'lng': location.longitude,
      'osmNodeId': osmNodeId,
      'roadName': roadName,
      'severity': severity.index,
      'issueType': issueType,
      'description': description,
      'imageUrl': imageUrl,
      'timestamp': timestamp.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  factory RoadReport.fromJson(Map<String, dynamic> json) {
    return RoadReport(
      id: json['id'],
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      osmNodeId: json['osmNodeId'],
      roadName: json['roadName'],
      severity: Severity.values[json['severity']],
      issueType: json['issueType'] ?? 'Other',
      description: json['description'],
      imageUrl: json['imageUrl'],
      timestamp: DateTime.parse(json['timestamp']),
      isSynced: json['isSynced'] ?? true,
    );
  }
}

class RoadSegment {
  final String id;
  final List<LatLng> points;
  final String name;
  final String type;
  final double priorityScore;

  RoadSegment({
    required this.id,
    required this.points,
    required this.name,
    required this.type,
    required this.priorityScore,
  });

  Severity get severity {
    if (priorityScore >= 4.5) return Severity.level5;
    if (priorityScore >= 3.5) return Severity.level4;
    if (priorityScore >= 2.5) return Severity.level3;
    if (priorityScore >= 1.5) return Severity.level2;
    return Severity.level1;
  }
}
