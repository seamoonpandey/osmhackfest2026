import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/models.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<RoadReport> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final reports = await apiClient.getReports();
    // Sort by timestamp descending
    reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (mounted) {
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'MY ACTIVITY',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.5,
            color: AppTheme.primaryCoral,
          ),
        ),
        backgroundColor: AppTheme.surfaceWhite,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_edu_rounded, size: 64, color: Colors.black12),
                      const SizedBox(height: 16),
                      Text(
                        'No reports yet',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => _buildReportCard(_reports[index]),
                ),
    );
  }

  Widget _buildReportCard(RoadReport report) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 60,
                height: 60,
                color: Colors.grey[100],
                child: report.imageUrl != null
                    ? (report.imageUrl!.startsWith('http')
                        ? Image.network(report.imageUrl!, fit: BoxFit.cover)
                        : Image.file(File(report.imageUrl!), fit: BoxFit.cover))
                    : Icon(Icons.location_on_rounded, color: _getSeverityColor(report.severity)),
              ),
            ),
            title: Text(
              report.roadName ?? 'Unknown Location',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 const SizedBox(height: 4),
                 Text(report.issueType?.toUpperCase() ?? 'ISSUE', 
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.black45)),
                 const SizedBox(height: 4),
                 Text(timeago.format(report.timestamp), style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusBadge(report.isSynced),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isSynced) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSynced ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSynced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded, 
               size: 12, 
               color: isSynced ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            isSynced ? 'Synced' : 'Pending',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isSynced ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(Severity severity) {
     switch (severity) {
       case Severity.level1: return const Color(0xFF4CAF50);
       case Severity.level2: return const Color(0xFF8BC34A);
       case Severity.level3: return const Color(0xFFFFC107);
       case Severity.level4: return const Color(0xFFFF9800);
       case Severity.level5: return const Color(0xFFF44336);
     }
  }
}
