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
  Severity _selectedSeverity = Severity.medium;
  Position? _currentPosition;
  CameraController? _cameraController;
  XFile? _capturedImage;
  String? _roadName;
  String? _aiAnalysis;
  String? _aiImageUrl;
  bool _isLocating = false;
  bool _isSubmitting = false;
  bool _isAnalyzing = false;

  Future<void> _runAIDiagnostic() async {
    if (_capturedImage == null) return;
    setState(() => _isAnalyzing = true);
    
    try {
      final result = await apiClient.analyzePothole(_capturedImage!.path);
      if (mounted) {
        setState(() {
          _aiAnalysis = result['analysis'];
          _aiImageUrl = result['imageUrl'];
          
          // Collaborative AI: Suggest a severity based on analysis
          if (_aiAnalysis?.contains('areas identified') ?? false) {
            _selectedSeverity = Severity.high;
          }
          
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

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
      
      // Look up the road name
      String? road;
      try {
        road = await apiClient.reverseGeocode(position.latitude, position.longitude);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _roadName = road;
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

  Future<void> _submitReport() async {
    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a description')));
      return;
    }
    setState(() => _isSubmitting = true);
    final report = RoadReport(
      id: const Uuid().v4(),
      location: LatLng(_currentPosition?.latitude ?? 0, _currentPosition?.longitude ?? 0),
      roadName: _roadName,
      severity: _selectedSeverity,
      description: _descriptionController.text,
      timestamp: DateTime.now(),
      imageUrl: _capturedImage?.path,
      aiAnalysis: _aiAnalysis,
      aiImageUrl: _aiImageUrl,
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
                  _roadName ?? (_currentPosition != null ? 'Finding road...' : 'Locating...'),
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
                Text(
                  _roadName?.toUpperCase() ?? 'IDENTIFYING ROAD...',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: AppTheme.accentCyan,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildSeverityIcon(Severity.low, 'Minor', AppTheme.lowRisk),
                    const SizedBox(width: 12),
                    _buildSeverityIcon(Severity.medium, 'Repair', AppTheme.mediumRisk),
                    const SizedBox(width: 12),
                    _buildSeverityIcon(Severity.high, 'Urgent', AppTheme.highRisk),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _descriptionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Describe the issue...',
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
                if (_aiAnalysis != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppTheme.accentCyan, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "AI Suggestion: $_aiAnalysis",
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_capturedImage != null && _aiAnalysis == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isAnalyzing ? null : _runAIDiagnostic,
                        icon: _isAnalyzing 
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(_isAnalyzing ? 'ENGINE RUNNING...' : 'RUN AI DIAGNOSTIC'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentCyan,
                          side: const BorderSide(color: AppTheme.accentCyan),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
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
