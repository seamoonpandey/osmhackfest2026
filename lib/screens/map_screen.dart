import 'dart:ui';
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
  final TextEditingController _searchController = TextEditingController();
  List<RoadReport> _reports = [];
  List<RoadSegment> _segments = [];
  bool _isLoading = true;
  bool _showSearchResults = false;

  final List<Map<String, dynamic>> _mockSearchResults = [
    {'name': 'Durbar Marg', 'location': const LatLng(27.7120, 85.3240)},
    {'name': 'Lazimpat Road', 'location': const LatLng(27.7185, 85.3200)},
    {'name': 'Balaju Bypass', 'location': const LatLng(27.7300, 85.3000)},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
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

  void _handleSearch(String query) {
    if (query.isNotEmpty) {
      setState(() => _showSearchResults = true);
    } else {
      setState(() => _showSearchResults = false);
    }
  }

  void _moveToLocation(LatLng location) {
    _mapController.move(location, 16.0);
    setState(() {
      _showSearchResults = false;
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
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
        title: Text('ROAD MONITOR', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
                tileBuilder: (context, widget, chunk) => ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    -0.2126, -0.7152, -0.0722, 0, 255,
                    -0.2126, -0.7152, -0.0722, 0, 255,
                    -0.2126, -0.7152, -0.0722, 0, 255,
                    0, 0, 0, 1, 0,
                  ]),
                  child: widget,
                ),
              ),
              PolylineLayer(
                polylines: [
                  ..._segments.map((segment) => Polyline(
                        points: segment.points,
                        color: Colors.white.withOpacity(0.05),
                        strokeWidth: 16.0,
                        strokeCap: StrokeCap.round,
                      )),
                  ..._segments.map((segment) => Polyline(
                        points: segment.points,
                        color: _getSeverityColor(segment.severity).withOpacity(0.3),
                        strokeWidth: 10.0,
                        strokeCap: StrokeCap.round,
                      )),
                  ..._segments.map((segment) => Polyline(
                        points: segment.points,
                        color: _getSeverityColor(segment.severity),
                        strokeWidth: 3.0,
                        strokeCap: StrokeCap.round,
                      )),
                ],
              ),
              MarkerLayer(
                markers: _reports.map((report) => Marker(
                      point: report.location,
                      width: 60,
                      height: 60,
                      child: GestureDetector(
                        onTap: () => _showReportDetails(report),
                        child: _buildMarker(report),
                      ),
                    )).toList(),
              ),
            ],
          ),
          _buildSearchOverlay(),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          _buildLegend(),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildMarker(RoadReport report) {
    final color = _getSeverityColor(report.severity);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
        ),
        Icon(Icons.location_on_rounded, color: color, size: 30),
      ],
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: 20,
      left: 16,
      right: 16,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBg.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _handleSearch,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search for roads or areas...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search_rounded, color: AppTheme.primaryBlue),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
              ),
            ),
          ),
          if (_showSearchResults)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: _mockSearchResults
                    .where((res) => res['name'].toString().toLowerCase().contains(_searchController.text.toLowerCase()))
                    .map((res) => ListTile(
                          title: Text(res['name'], style: const TextStyle(color: Colors.white)),
                          leading: const Icon(Icons.place_rounded, color: Colors.white54),
                          onTap: () => _moveToLocation(res['location']),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      bottom: 24,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem('URGENT', AppTheme.highRisk),
                const SizedBox(height: 10),
                _buildLegendItem('REPAIR', AppTheme.mediumRisk),
                const SizedBox(height: 10),
                _buildLegendItem('STABLE', AppTheme.lowRisk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, anim, second) => const ReportScreen(),
              transitionsBuilder: (context, anim, second, child) => FadeTransition(opacity: anim, child: child),
            ),
          );
          if (result == true) _loadData();
        },
        label: const Text('REPORT ISSUE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        icon: const Icon(Icons.add_a_photo_rounded),
        elevation: 8,
        shadowColor: AppTheme.primaryBlue.withOpacity(0.5),
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
