import 'package:latlong2/latlong.dart';
import 'package:hive/hive.dart';

part 'models.g.dart';

@HiveType(typeId: 0)
enum Severity { 
  @HiveField(0) low, 
  @HiveField(1) medium, 
  @HiveField(2) high 
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

  RoadReport({
    required this.id,
    double? lat,
    double? lng,
    LatLng? location,
    this.osmNodeId,
    this.roadName,
    required this.severity,
    required this.description,
    this.imageUrl,
    required this.timestamp,
    this.isSynced = false,
  })  : this.lat = lat ?? location?.latitude ?? 0.0,
        this.lng = lng ?? location?.longitude ?? 0.0;

  LatLng get location => LatLng(lat, lng);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': location.latitude,
      'lng': location.longitude,
      'osmNodeId': osmNodeId,
      'roadName': roadName,
      'severity': severity.index,
      'description': description,
      'imageUrl': imageUrl,
      'timestamp': timestamp.toIso8601String(),
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
    if (priorityScore >= 4.0) return Severity.high;
    if (priorityScore >= 2.5) return Severity.medium;
    return Severity.low;
  }
}
