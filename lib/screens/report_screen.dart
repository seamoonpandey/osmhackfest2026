import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _isLocating = false;
      });
    } catch (e) {
      setState(() => _isLocating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      print('Camera error: $e');
    }
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
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<void> _submitReport() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for location...')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final report = RoadReport(
      id: const Uuid().v4(),
      location: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      severity: _selectedSeverity,
      description: _descriptionController.text,
      timestamp: DateTime.now(),
      imageUrl: _capturedImage?.path,
    );

    await apiClient.submitReport(report);

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Report'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Location Status'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentPosition != null ? Icons.location_on : Icons.location_off,
                    color: _currentPosition != null ? AppTheme.lowRisk : AppTheme.highRisk,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPosition != null
                              ? 'Location Captured'
                              : (_isLocating ? 'Capturing Location...' : 'Location Missing'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_currentPosition != null)
                          Text(
                            '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                  if (_isLocating)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Issue Evidence'),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: _capturedImage != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
                          // Placeholder for web/sim where File(path) might fail
                          const Center(child: Icon(Icons.image, size: 48, color: Colors.white24)),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => setState(() => _capturedImage = null),
                              style: IconButton.styleFrom(backgroundColor: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    : (_cameraController != null && _cameraController!.value.isInitialized
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(_cameraController!),
                              Center(
                                child: IconButton(
                                  icon: const Icon(Icons.camera_alt, size: 48, color: Colors.white),
                                  onPressed: _takePicture,
                                ),
                              ),
                            ],
                          )
                        : const Center(child: CircularProgressIndicator())),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Severity Level'),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSeverityTab(Severity.low, 'Low', AppTheme.lowRisk),
                const SizedBox(width: 8),
                _buildSeverityTab(Severity.medium, 'Medium', AppTheme.mediumRisk),
                const SizedBox(width: 8),
                _buildSeverityTab(Severity.high, 'High', AppTheme.highRisk),
              ],
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Description'),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe the road condition...',
                filled: true,
                fillColor: AppTheme.surfaceBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Submit Report',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppTheme.accentCyan,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSeverityTab(Severity severity, String label, Color color) {
    final isSelected = _selectedSeverity == severity;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSeverity = severity),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white : color.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
