import 'package:latlong2/latlong.dart';

enum Severity { low, medium, high }

class RoadReport {
  final String id;
  final LatLng location;
  final String? osmNodeId;
  final String? roadName;
  final Severity severity;
  final String description;
  final String? imageUrl;
  final DateTime timestamp;

  RoadReport({
    required this.id,
    required this.location,
    this.osmNodeId,
    this.roadName,
    required this.severity,
    required this.description,
    this.imageUrl,
    required this.timestamp,
  });

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
      location: LatLng(json['lat'], json['lng']),
      osmNodeId: json['osmNodeId'],
      roadName: json['roadName'],
      severity: Severity.values[json['severity']],
      description: json['description'],
      imageUrl: json['imageUrl'],
      timestamp: DateTime.parse(json['timestamp']),
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
