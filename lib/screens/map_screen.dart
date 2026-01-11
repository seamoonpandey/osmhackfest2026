import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'report_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<RoadReport> _reports = [];
  List<RoadSegment> _segments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final reports = await apiClient.getReports();
    final segments = await apiClient.getRoadSegments();
    if (mounted) {
      setState(() {
        _reports = reports;
        _segments = segments;
        _isLoading = false;
      });
    }
  }

  Color _getSeverityColor(Severity severity) {
    switch (severity) {
      case Severity.high:
        return AppTheme.highRisk;
      case Severity.medium:
        return AppTheme.mediumRisk;
      case Severity.low:
        return AppTheme.lowRisk;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Road Quality Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(27.7172, 85.3240),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.osmapp',
              ),
              PolylineLayer(
                polylines: _segments.map((segment) {
                  return Polyline(
                    points: segment.points,
                    color: _getSeverityColor(segment.severity).withOpacity(0.7),
                    strokeWidth: 6.0,
                    isDotted: false,
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: _reports.map((report) {
                  return Marker(
                    point: report.location,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _showReportDetails(report),
                      child: Icon(
                        Icons.location_on,
                        color: _getSeverityColor(report.severity),
                        size: 40,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              children: [
                _buildLegendItem('High Risk', AppTheme.highRisk),
                const SizedBox(height: 8),
                _buildLegendItem('Medium Risk', AppTheme.mediumRisk),
                const SizedBox(height: 8),
                _buildLegendItem('Low Risk', AppTheme.lowRisk),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReportScreen()),
          );
          if (result == true) {
            _loadData();
          }
        },
        label: const Text('Report Issue'),
        icon: const Icon(Icons.add_location_alt),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showReportDetails(RoadReport report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    report.roadName ?? 'Unknown Road',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(report.severity).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      report.severity.name.toUpperCase(),
                      style: TextStyle(
                        color: _getSeverityColor(report.severity),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                report.description,
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Text(
                    'Reported at: ${report.timestamp.hour}:${report.timestamp.minute}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
