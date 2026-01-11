import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
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
                color: AppTheme.primaryBlue.withOpacity(1 - _controller.value),
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryBlue,
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
  LatLng? _currentPosition;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSearchingUI = false;
  List<Map<String, dynamic>> _searchResults = [];
  DateTime? _lastSearchTime;
  Set<Severity> _visibleSeverities = Set.from(Severity.values);
  bool _showUserLocation = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startLocationListening();
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
    
    // Get current position for initial view
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) {
        _mapController.move(LatLng(position.latitude, position.longitude), 14.0);
      }
    } catch (e) {
      // Fallback to default if location fails
    }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
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
        title: _isSearchingUI
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _handleSearch,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search locations...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              )
            : Text('ROAD MONITOR',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
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
              MarkerLayer(
                markers: [
                  ..._reports
                      .where((r) => _visibleSeverities.contains(r.severity))
                      .map((report) => Marker(
                        point: report.location,
                        width: 60,
                        height: 60,
                        child: GestureDetector(
                          onTap: () => _showReportDetails(report),
                          child: _buildMarker(report),
                        ),
                      )),
                  if (_currentPosition != null && _showUserLocation)
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
              backgroundColor: AppTheme.surfaceBg.withOpacity(0.8),
              child: const Icon(Icons.my_location_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
      drawer: _buildSidebar(),
    );
  }

  Widget _buildSidebar() {
    return Drawer(
      backgroundColor: AppTheme.surfaceBg,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                border: const Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MAP SETTINGS',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppTheme.primaryBlue,
                          letterSpacing: 1.5)),
                  const Text('Customize your monitor view',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('VISIBLE LAYERS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white38,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  _buildSidebarToggle(
                    'My Location',
                    Icons.my_location_rounded,
                    _showUserLocation,
                    (val) => setState(() => _showUserLocation = val),
                  ),
                  const SizedBox(height: 32),
                  const Text('ROAD FILTERS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white38,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  _buildSidebarFilter('Urgent Issues', AppTheme.highRisk, Severity.high),
                  _buildSidebarFilter('Repair Needed', AppTheme.mediumRisk, Severity.medium),
                  _buildSidebarFilter('Stable Roads', AppTheme.lowRisk, Severity.low),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarToggle(String label, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryBlue, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Switch.adaptive(
            value: value,
            activeColor: AppTheme.primaryBlue,
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
      title: Text(label,
          style: TextStyle(
              color: isVisible ? Colors.white : Colors.white38,
              fontWeight: isVisible ? FontWeight.bold : FontWeight.normal)),
      trailing: Checkbox(
        value: isVisible,
        onChanged: (val) {
          setState(() {
            if (val == true) {
              _visibleSeverities.add(severity);
            } else {
              _visibleSeverities.remove(severity);
            }
          });
        },
        activeColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildMarker(RoadReport report) {
    final color = _getSeverityColor(report.severity);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Marker Shadow/Glow
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        // Main Marker Container
        Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: report.imageUrl != null
                ? (report.imageUrl!.startsWith('http')
                    ? Image.network(
                        report.imageUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: color.withOpacity(0.1),
                            child: const Center(child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))),
                          );
                        },
                        errorBuilder: (c, e, s) => Container(
                          color: color,
                          child: const Icon(Icons.broken_image_rounded, color: Colors.white, size: 18),
                        ),
                      )
                    : Image.file(
                        File(report.imageUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          color: color,
                          child: const Icon(Icons.no_photography_rounded, color: Colors.white, size: 18),
                        ),
                      ))
                : Container(
                    color: color,
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  ),
          ),
        ),
        // Risk Badge (Bottom Right)
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchOverlay() {
    if (!_isSearchingUI || (_searchResults.isEmpty && !_isSearching && _searchController.text.length < 3)) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg.withOpacity(0.9),
              border: const Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: _searchResults.isEmpty && !_isSearching
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text('No places found', style: TextStyle(color: Colors.white54)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _searchResults.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final res = _searchResults[index];
                      return ListTile(
                        title: Text(
                          res['name'], 
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)
                        ),
                        leading: const Icon(Icons.place_rounded, color: AppTheme.primaryBlue),
                        onTap: () => _moveToLocation(LatLng(res['lat'], res['lng'])),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      bottom: 24,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg.withOpacity(0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('FILTERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                _buildLegendItem('URGENT', AppTheme.highRisk, Severity.high),
                const SizedBox(height: 8),
                _buildLegendItem('REPAIR', AppTheme.mediumRisk, Severity.medium),
                const SizedBox(height: 8),
                _buildLegendItem('STABLE', AppTheme.lowRisk, Severity.low),
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
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isVisible ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVisible ? color.withOpacity(0.5) : Colors.white10,
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
                boxShadow: isVisible ? [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)
                ] : null,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 11, 
                fontWeight: FontWeight.bold,
                color: isVisible ? Colors.white : Colors.white38,
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
              if (report.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: report.imageUrl!.startsWith('http')
                        ? Image.network(
                            report.imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AppTheme.surfaceElevated,
                              child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 48),
                            ),
                          )
                        : Image.file(
                            File(report.imageUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AppTheme.surfaceElevated,
                              child: const Icon(Icons.no_photography_rounded, color: Colors.white24, size: 48),
                            ),
                          ),
                  ),
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
