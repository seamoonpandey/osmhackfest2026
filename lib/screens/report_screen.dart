import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _descriptionController = TextEditingController();
  Severity _selectedSeverity = Severity.level3;
  String _selectedIssueType = 'Pothole';
  final List<String> _issueTypes = ['Pothole', 'Crack', 'Drainage', 'Faded Markings', 'Obstruction', 'Other'];
  Position? _currentPosition;
  CameraController? _cameraController;
  XFile? _capturedImage;
  String? _roadName;
  List<String> _nearbyRoads = [];
  bool _isLocating = false;
  bool _isSubmitting = false;


  @override
  void initState() {
    super.initState();
    _initLocation();
    _initCamera();
  }

  Future<void> _initLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition();
      
      // Look up the road name and nearby roads
      String? road;
      List<String> roads = [];
      try {
        road = await apiClient.reverseGeocode(position.latitude, position.longitude);
        roads = await apiClient.getNearbyRoads(position.latitude, position.longitude);
        
        // Ensure the default road is in the list
        if (road != null && !roads.contains(road)) {
          roads.insert(0, road);
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _roadName = road ?? (roads.isNotEmpty ? roads.first : null);
          _nearbyRoads = roads;
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _cameraController = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {}
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final image = await _cameraController!.takePicture();
      setState(() => _capturedImage = image);
    } catch (e) {}
  }

  void _showRoadPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SELECT NEARBY ROAD',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.white38,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 32),
                itemCount: _nearbyRoads.length,
                itemBuilder: (context, index) {
                  final road = _nearbyRoads[index];
                  bool isSelected = road == _roadName;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                    leading: Icon(
                      Icons.add_location,
                      color: isSelected ? AppTheme.accentCyan : Colors.white24,
                      size: 20,
                    ),
                    title: Text(
                      road,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.accentCyan, size: 20) : null,
                    onTap: () {
                      setState(() => _roadName = road);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a description')));
      return;
    }
    setState(() => _isSubmitting = true);

    // Final attempt to get road name if still null
    if (_roadName == null && _currentPosition != null) {
      try {
        _roadName = await apiClient.reverseGeocode(_currentPosition!.latitude, _currentPosition!.longitude);
      } catch (_) {}
    }

    final report = RoadReport(
      id: const Uuid().v4(),
      location: LatLng(_currentPosition?.latitude ?? 0, _currentPosition?.longitude ?? 0),
      roadName: _roadName,
      severity: _selectedSeverity,
      issueType: _selectedIssueType,
      description: _descriptionController.text,
      timestamp: DateTime.now(),
      imageUrl: _capturedImage?.path,
    );
    await apiClient.submitReport(report);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          _buildCameraPreview(),
          _buildOverlayControls(),
          if (_isSubmitting)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_capturedImage != null) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(File(_capturedImage!.path)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()));
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize!.height,
          height: _cameraController!.value.previewSize!.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildOverlayControls() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          const Spacer(),
          _buildBottomCard(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Colors.black26,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(
                  _currentPosition != null ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 16,
                  color: _currentPosition != null ? AppTheme.lowRisk : Colors.white54,
                ),
                const SizedBox(width: 8),
                Text(
                  _roadName ?? (_isLocating ? 'Finding road...' : 'Road identity pending'),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBg.withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_capturedImage == null) ...[
                const Text(
                  'Capture Road Evidence',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _roadName?.toUpperCase() ?? 'DETERMINING LOCATION...',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppTheme.accentCyan,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_nearbyRoads.length > 1)
                      TextButton.icon(
                        onPressed: _showRoadPicker,
                        icon: const Icon(Icons.edit_location_alt, size: 14, color: AppTheme.accentCyan),
                        label: Text(
                          'CHANGE',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (_isLocating && _roadName == null) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'ISSUE TYPE',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.white38,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _issueTypes.map((type) {
                      bool isSelected = _selectedIssueType == type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(type),
                          selected: isSelected,
                          onSelected: (val) => setState(() => _selectedIssueType = type),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          selectedColor: AppTheme.primaryBlue,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'SEVERITY SCALE (1-5)',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Colors.white38,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildSeverityIcon(Severity.level1, '1', const Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    _buildSeverityIcon(Severity.level2, '2', const Color(0xFF8BC34A)),
                    const SizedBox(width: 8),
                    _buildSeverityIcon(Severity.level3, '3', const Color(0xFFFFC107)),
                    const SizedBox(width: 8),
                    _buildSeverityIcon(Severity.level4, '4', const Color(0xFFFF9800)),
                    const SizedBox(width: 8),
                    _buildSeverityIcon(Severity.level5, '5', const Color(0xFFF44336)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Additional details...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _capturedImage = null),
                        child: const Text('Retake', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentCyan,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeverityIcon(Severity severity, String label, Color color) {
    bool isSelected = _selectedSeverity == severity;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSeverity = severity),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? Colors.white : Colors.transparent),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
