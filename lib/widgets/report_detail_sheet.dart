import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../core/theme.dart';

class ReportDetailSheet extends StatelessWidget {
  final RoadReport report;

  const ReportDetailSheet({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Image
          if (report.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    report.imageUrl!.startsWith('http')
                        ? Image.network(report.imageUrl!, fit: BoxFit.cover)
                        : Image.file(File(report.imageUrl!), fit: BoxFit.cover),
                    // Gradient overlay for text readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Title & Severity Badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (report.issueType ?? 'Other').toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.5,
                              color: Colors.black38,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.roadName ?? 'Unknown Road',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: const Color(0xFF212529),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildSeverityBadge(report.severity),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // 3. Metadata Grid
                Row(
                  children: [
                    Expanded(child: _buildInfoItem(Icons.access_time_filled_rounded, 'Reported', timeago.format(report.timestamp))),
                    Expanded(child: _buildInfoItem(Icons.sync_rounded, 'Status', report.isSynced ? 'Synced' : 'Pending')),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // 4. Description if available
                if (report.description != null && report.description!.isNotEmpty) ...[
                  Text(
                    'NOTES',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report.description!,
                    style: const TextStyle(color: Colors.black87, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                ],

                // 5. Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _launchMaps(report.lat, report.lng),
                    icon: const Icon(Icons.directions_rounded),
                    label: const Text('NAVIGATE TO LOCATION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryCoral,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24), // Bottom padding
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(Severity severity) {
    Color color;
    String label;
    
    switch (severity) {
      case Severity.level1:
        color = const Color(0xFF4CAF50);
        label = 'LOW';
        break;
      case Severity.level2:
        color = const Color(0xFF8BC34A);
        label = 'MED';
        break;
      case Severity.level3:
        color = const Color(0xFFFFC107);
        label = 'HIGH';
        break;
      case Severity.level4:
        color = const Color(0xFFFF9800);
        label = 'V.HIGH';
        break;
      case Severity.level5:
        color = const Color(0xFFF44336);
        label = 'CRITICAL';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.black38),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF212529)),
        ),
      ],
    );
  }

  Future<void> _launchMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
