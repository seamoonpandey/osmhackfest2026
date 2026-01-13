import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart'; // Clustering
import '../widgets/report_detail_sheet.dart'; // Detail Sheet
import '../models/models.dart';
import 'report_screen.dart';
import 'history_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _UserLocationMarker extends StatefulWidget {
  const _UserLocationMarker();

  @override
  State<_UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<_UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40 * _controller.value,
              height: 40 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryCoral.withOpacity(1 - _controller.value),
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryCoral,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<RoadReport> _reports = [];
  List<RoadSegment> _segments = [];
  List<Polyline> _cachedPolylines = []; // Cached polylines to avoid rebuilding
  LatLng? _currentPosition;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSearchingUI = false;
  List<Map<String, dynamic>> _searchResults = [];
  DateTime? _lastSearchTime;
  Set<Severity> _visibleSeverities = Set.from(Severity.values);
  bool _showUserLocation = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _startLocationListening();
    _setupAutoSync();
  }

  void _setupAutoSync() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        _performAutoSync();
      }
    });
  }

  Future<void> _performAutoSync() async {
    // Optional: Check if we actually have unsynced data first could be an optimization
    // For now, we just try to sync. The API client should handle empty lists gracefully.
    try {
      final syncedCount = await apiClient.syncUnsyncedReports();
      if (syncedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Back online: $syncedCount reports synced!'),
            backgroundColor: AppTheme.lowRisk,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData(); // Refresh map data
      }
    } catch (e) {
      // Silent fail on auto-sync errors to not annoy user
    }
  }

  void _startLocationListening() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Attempt to sync pending reports on load
    apiClient.syncUnsyncedReports();

    // Get current position for initial view
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          14.0,
        );
      }
    } catch (e) {
      // Fallback to default if location fails
    }

    // Load segments first to populate cache for name lookup
    final segments = await apiClient.getRoadSegments();
    final reports = await apiClient.getReports();
    if (mounted) {
      setState(() {
        _reports = reports;
        _segments = segments;
        _rebuildPolylines();
        _isLoading = false;
      });
    }
  }

  /// Rebuild cached polylines - call when segments or visibility changes
  void _rebuildPolylines() {
    _cachedPolylines = _segments
        .where((segment) => _visibleSeverities.contains(segment.severity))
        .map((segment) {
          final color = _getSeverityColor(segment.severity);
          return Polyline(
            points: segment.points,
            color: color.withOpacity(0.7),
            strokeWidth: 4.0,
            borderColor: Colors.black12,
            borderStrokeWidth: 1.0,
          );
        })
        .toList();
  }

  void _handleSearch(String query) async {
    if (query.length < 3) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Debouncing to avoid hitting API too hard
    final now = DateTime.now();
    _lastSearchTime = now;
    await Future.delayed(const Duration(milliseconds: 600));
    if (_lastSearchTime != now) return;

    final results = await apiClient.searchPlaces(query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _goToCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
    }
  }

  void _moveToLocation(LatLng location) {
    _mapController.move(location, 16.0);
    setState(() {
      _isSearchingUI = false;
      _searchController.clear();
      _searchResults = [];
      FocusScope.of(context).unfocus();
    });
  }

  Color _getSeverityColor(Severity severity) {
    switch (severity) {
      case Severity.level1:
        return const Color(0xFF4CAF50);
      case Severity.level2:
        return const Color(0xFF8BC34A);
      case Severity.level3:
        return const Color(0xFFFFC107);
      case Severity.level4:
        return const Color(0xFFFF9800);
      case Severity.level5:
        return const Color(0xFFF44336);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearchingUI
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _handleSearch,
                style: const TextStyle(color: Color(0xFF212529), fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search locations...',
                  hintStyle: TextStyle(color: Colors.black38),
                  border: InputBorder.none,
                ),
              )
            : Text(
                'ROADWATCH',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 2,
                  color: AppTheme.primaryCoral,
                ),
              ),
        leading: _isSearchingUI
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  setState(() {
                    _isSearchingUI = false;
                    _searchController.clear();
                    _searchResults = [];
                  });
                },
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: [
          if (!_isSearchingUI)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _isSearchingUI = true),
            ),
          if (_isSearchingUI && _searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _searchController.clear();
                _searchResults = [];
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
        bottom: _isSearchingUI && _isSearching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
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
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 45,
                  size: const Size(40, 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  markers: _reports
                      .where(
                        (report) =>
                            _visibleSeverities.contains(report.severity),
                      )
                      .map(
                        (report) => Marker(
                          point: report.location,
                          width: 60,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => _showReportDetails(report),
                            child: _buildMarker(report),
                          ),
                        ),
                      )
                      .toList(),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(20),
                        color: AppTheme.primaryCoral,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_currentPosition != null && _showUserLocation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 60,
                      height: 60,
                      child: const _UserLocationMarker(),
                    ),
                  ],
                ),
            ],
          ),
          _buildSearchOverlay(),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton.small(
              heroTag: 'location_fab',
              onPressed: _goToCurrentLocation,
              backgroundColor: AppTheme.surfaceWhite,
              child: const Icon(
                Icons.my_location_rounded,
                color: AppTheme.primaryCoral,
              ),
            ),
          ),
          _buildFloatingVerticalLegend(),
        ],
      ),
      floatingActionButton: _buildFAB(),
      drawer: _buildSidebar(),
    );
  }

  Widget _buildSidebar() {
    return Drawer(
      backgroundColor: AppTheme.surfaceWhite,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.primaryCoral.withOpacity(0.05),
                border: const Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ROAD WATCH',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppTheme.primaryCoral,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Text(
                    'Precision Infrastructure Monitor',
                    style: TextStyle(color: Colors.black38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'VISIBLE LAYERS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black38,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSidebarToggle(
                    'My Location',
                    Icons.my_location_rounded,
                    _showUserLocation,
                    (val) => setState(() => _showUserLocation = val),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(
                      Icons.history_rounded,
                      color: AppTheme.primaryCoral,
                    ),
                    title: const Text(
                      'My Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212529),
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistoryScreen(),
                        ),
                      );
                    },
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    dense: true,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'ROAD FILTERS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black38,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSidebarFilter(
                    'Level 5 (Critical)',
                    const Color(0xFFF44336),
                    Severity.level5,
                  ),
                  _buildSidebarFilter(
                    'Level 4 (Very High)',
                    const Color(0xFFFF9800),
                    Severity.level4,
                  ),
                  _buildSidebarFilter(
                    'Level 3 (High)',
                    const Color(0xFFFFC107),
                    Severity.level3,
                  ),
                  _buildSidebarFilter(
                    'Level 2 (Medium)',
                    const Color(0xFF8BC34A),
                    Severity.level2,
                  ),
                  _buildSidebarFilter(
                    'Level 1 (Low)',
                    const Color(0xFF4CAF50),
                    Severity.level1,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting Cloud Sync...')),
                      );
                      await apiClient.syncUnsyncedReports();
                      await _loadData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sync Complete!')),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('SYNC DATA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryCoral.withOpacity(0.1),
                      foregroundColor: AppTheme.primaryCoral,
                      side: const BorderSide(color: AppTheme.primaryCoral),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarToggle(
    String label,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryCoral, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF212529),
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: value,
            activeColor: AppTheme.primaryCoral,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFilter(String label, Color color, Severity severity) {
    final bool isVisible = _visibleSeverities.contains(severity);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: isVisible ? color : color.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isVisible ? const Color(0xFF212529) : Colors.black38,
          fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Checkbox(
        value: isVisible,
        onChanged: (val) {
          setState(() {
            if (val == true) {
              _visibleSeverities.add(severity);
            } else {
              _visibleSeverities.remove(severity);
            }
            _rebuildPolylines();
          });
        },
        activeColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildMarker(RoadReport report) {
    final color = _getSeverityColor(report.severity);
    const double size = 44.0;

    return Transform.translate(
      offset: const Offset(0, -size / 2), // Shift up so tip is at coordinate
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pin Tip (The Triangle)
          Positioned(
            bottom: 0,
            child: CustomPaint(
              size: const Size(16, 16),
              painter: _PinTipPainter(color),
            ),
          ),
          // Pin Head (The Circle)
          Positioned(
            top: 0,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(1.5),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(size),
                        child: report.imageUrl != null
                            ? (report.imageUrl!.startsWith('http')
                                  ? Image.network(
                                      report.imageUrl!,
                                      fit: BoxFit.cover,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;
                                            return Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: color.withOpacity(0.5),
                                              ),
                                            );
                                          },
                                      errorBuilder: (c, e, s) => Icon(
                                        Icons.broken_image_rounded,
                                        color: color,
                                        size: 20,
                                      ),
                                    )
                                  : Image.file(
                                      File(report.imageUrl!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Icon(
                                        Icons.no_photography_rounded,
                                        color: color,
                                        size: 20,
                                      ),
                                    ))
                            : Icon(
                                Icons.warning_amber_rounded,
                                color: color,
                                size: 22,
                              ),
                      ),
                    ),
                    if (!report.isSynced)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.sync_rounded,
                            color: AppTheme.primaryCoral,
                            size: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingVerticalLegend() {
    return Positioned(
      bottom: 24,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLegendItem(
              'Critical',
              const Color(0xFFF44336),
              Severity.level5,
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              'Very High',
              const Color(0xFFFF9800),
              Severity.level4,
            ),
            const SizedBox(height: 8),
            _buildLegendItem('High', const Color(0xFFFFC107), Severity.level3),
            const SizedBox(height: 8),
            _buildLegendItem(
              'Medium',
              const Color(0xFF8BC34A),
              Severity.level2,
            ),
            const SizedBox(height: 8),
            _buildLegendItem('Low', const Color(0xFF4CAF50), Severity.level1),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child:
          (!_isSearchingUI ||
              (_searchResults.isEmpty &&
                  !_isSearching &&
                  _searchController.text.length < 3))
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Positioned(
              key: const ValueKey('search_results'),
              top: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceWhite,
                      border: const Border(
                        bottom: BorderSide(color: Colors.black12),
                      ),
                    ),
                    child: _searchResults.isEmpty && !_isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'No places found',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _searchResults.length,
                            separatorBuilder: (context, index) =>
                                const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final res = _searchResults[index];
                              return ListTile(
                                title: Text(
                                  res['name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF212529),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                leading: const Icon(
                                  Icons.place_rounded,
                                  color: AppTheme.primaryCoral,
                                ),
                                onTap: () => _moveToLocation(
                                  LatLng(res['lat'], res['lng']),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSimpleLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Colors.black54,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
              transitionsBuilder: (context, anim, second, child) =>
                  FadeTransition(opacity: anim, child: child),
            ),
          );
          if (result == true) _loadData();
        },
        label: const Text(
          'REPORT ISSUE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        icon: const Icon(Icons.add_a_photo_rounded),
        elevation: 8,
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, Severity severity) {
    final bool isVisible = _visibleSeverities.contains(severity);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isVisible) {
            _visibleSeverities.remove(severity);
          } else {
            _visibleSeverities.add(severity);
          }
          _rebuildPolylines();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isVisible ? color.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVisible ? color.withOpacity(0.3) : Colors.black12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isVisible ? color : color.withOpacity(0.2),
                shape: BoxShape.circle,
                boxShadow: isVisible
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isVisible ? const Color(0xFF212529) : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDetails(RoadReport report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ReportDetailSheet(report: report),
    );
  }
}

class _PinTipPainter extends CustomPainter {
  final Color color;
  _PinTipPainter(this.color);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;

    final path = ui.Path();
    path.moveTo(0, 0);
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
