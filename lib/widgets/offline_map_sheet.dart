import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/idr_pipeline.dart';
import '../services/osm_download_service.dart';

/// Modal bottom sheet for switching active offline road maps and downloading new city/minor road grids in-app.
class OfflineMapSheet extends StatefulWidget {
  const OfflineMapSheet({super.key});

  @override
  State<OfflineMapSheet> createState() => _OfflineMapSheetState();
}

class _OfflineMapSheetState extends State<OfflineMapSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<DownloadedMapFile> _downloadedFiles = [];
  bool _isLoadingFiles = true;

  // Downloader Form State
  final _nameController = TextEditingController(text: 'pune_urban_full');
  final _southController = TextEditingController(text: '18.500');
  final _westController = TextEditingController(text: '73.810');
  final _northController = TextEditingController(text: '18.540');
  final _eastController = TextEditingController(text: '73.865');
  RoadLevel _selectedLevel = RoadLevel.minorRoads;

  bool _isDownloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0.0;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshDownloadedFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _southController.dispose();
    _westController.dispose();
    _northController.dispose();
    _eastController.dispose();
    super.dispose();
  }

  Future<void> _refreshDownloadedFiles() async {
    setState(() => _isLoadingFiles = true);
    final files = await OsmDownloadService.listDownloadedMaps();
    if (mounted) {
      setState(() {
        _downloadedFiles = files;
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _startDownload(IdrPipeline pipeline) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _downloadError = 'Please enter a name for the map');
      return;
    }

    final south = double.tryParse(_southController.text.trim());
    final west = double.tryParse(_westController.text.trim());
    final north = double.tryParse(_northController.text.trim());
    final east = double.tryParse(_eastController.text.trim());

    if (south == null || west == null || north == null || east == null) {
      setState(() => _downloadError = 'Please enter valid coordinate numbers for the bounding box');
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadError = null;
      _downloadStatus = 'Starting download...';
      _downloadProgress = 0.05;
    });

    try {
      final file = await OsmDownloadService.downloadArea(
        mapName: name,
        south: south,
        west: west,
        north: north,
        east: east,
        level: _selectedLevel,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _downloadStatus = status;
              _downloadProgress = progress;
            });
          }
        },
      );

      // Auto-load into pipeline
      await pipeline.loadOfflineOsmMapFromFile(file, mapName: name);
      await _refreshDownloadedFiles();

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = 'Successfully loaded into IDR!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Activated "$name" with ${_selectedLevel.label}!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _download300mSmallStreets(IdrPipeline pipeline) async {
    final lat = pipeline.currentLatitude ?? pipeline.sensorService.refLat;
    final lon = pipeline.currentLongitude ?? pipeline.sensorService.refLon;

    if (lat == null || lon == null) {
      await pipeline.forceRefreshGps();
      final freshLat = pipeline.currentLatitude ?? pipeline.sensorService.refLat;
      final freshLon = pipeline.currentLongitude ?? pipeline.sensorService.refLon;
      if (freshLat == null || freshLon == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS fix required to download local 300m small streets.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _downloadError = null;
      _downloadStatus = 'Downloading 300m micro-grid of small streets...';
      _downloadProgress = 0.1;
    });

    try {
      final success = await pipeline.dynamicMapService.trigger300mSmallStreetsDownload(pipeline);
      await _refreshDownloadedFiles();

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = success ? 1.0 : 0.0;
          _downloadStatus = success ? 'Loaded 300m small street grid!' : 'Download failed';
        });
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Loaded 300m small streets & residential lanes (${pipeline.activeRoadBranchCount} roads)!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _tabController.animateTo(0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title & Active Map Strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map, color: Color(0xFF38BDF8), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OFFLINE MAP-MATCHING',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Active: Local Radius (${pipeline.activeRoadBranchCount} roads)',
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF34D399),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF38BDF8),
            labelColor: const Color(0xFF38BDF8),
            unselectedLabelColor: const Color(0xFF94A3B8),
            labelStyle: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'OFFLINE MAPS', icon: Icon(Icons.layers, size: 18)),
              Tab(text: 'DOWNLOAD MINOR ROADS', icon: Icon(Icons.cloud_download, size: 18)),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMapsListTab(pipeline),
                _buildDownloaderTab(pipeline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: Available Maps
  Widget _buildMapsListTab(IdrPipeline pipeline) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDynamicMapEngineCard(pipeline),
        const SizedBox(height: 16),

        // User Downloaded Maps Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DOWNLOADED LOCAL MAPS',
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: const Color(0xFF64748B),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF94A3B8)),
              onPressed: _refreshDownloadedFiles,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_isLoadingFiles)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
        else if (_downloadedFiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Center(
              child: Text(
                'No custom maps downloaded yet.\nUse the "DOWNLOAD MINOR ROADS" tab to download any city.',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          )
        else
          ..._downloadedFiles.map((f) {
            return Card(
              color: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(
                  color: Color(0xFF334155),
                ),
              ),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.storage, color: Color(0xFF38BDF8), size: 20),
                title: Text(
                  f.name,
                  style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                subtitle: Text(
                  'Size: ${f.formattedSize}',
                  style: GoogleFonts.rajdhani(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () async {
                        await pipeline.loadOfflineOsmMapFromFile(File(f.filePath), mapName: f.name);
                      },
                      child: Text('LOAD', style: GoogleFonts.rajdhani(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                      onPressed: () async {
                        await OsmDownloadService.deleteDownloadedMap(f.filePath);
                        await _refreshDownloadedFiles();
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDynamicMapEngineCard(IdrPipeline pipeline) {
    final dynamicService = pipeline.dynamicMapService;
    return ListenableBuilder(
      listenable: dynamicService,
      builder: (context, _) {
        final isDownloading = dynamicService.isDownloading;
        final bufferFraction = (dynamicService.distanceMovedSinceCenterKm / dynamicService.bufferKm).clamp(0.0, 1.0);
        final hasCenter = dynamicService.activeCenterLat != null && dynamicService.activeCenterLon != null;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDownloading
                  ? const Color(0xFF38BDF8)
                  : (dynamicService.isAutoDynamicEnabled ? const Color(0xFF0284C7) : const Color(0xFF334155)),
              width: isDownloading ? 2.0 : 1.2,
            ),
            boxShadow: [
              if (isDownloading)
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Auto-Toggle
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.radar,
                      color: isDownloading ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AUTONOMOUS 50KM DYNAMIC ENGINE',
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '50 km Radius • 25 km Buffer • Auto-Prune Old Tiles',
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: dynamicService.isAutoDynamicEnabled,
                    activeThumbColor: const Color(0xFF10B981),
                    activeTrackColor: const Color(0xFF064E3B),
                    inactiveThumbColor: const Color(0xFF64748B),
                    inactiveTrackColor: const Color(0xFF1E293B),
                    onChanged: (val) {
                      dynamicService.setAutoDynamicEnabled(val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 25km Buffer Displacement Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DISPLACEMENT FROM 50KM CENTER',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    hasCenter
                        ? '${dynamicService.distanceMovedSinceCenterKm.toStringAsFixed(1)} / ${dynamicService.bufferKm.toStringAsFixed(0)} km (Next download in ${dynamicService.remainingBufferDistanceKm.toStringAsFixed(1)} km)'
                        : 'Awaiting initial GPS fix',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: bufferFraction >= 0.9 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: hasCenter ? bufferFraction : 0.0,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF1E293B),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    bufferFraction >= 0.9 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Status line
              Row(
                children: [
                  Icon(
                    isDownloading ? Icons.sync : (hasCenter ? Icons.check_circle_outline : Icons.info_outline),
                    size: 14,
                    color: isDownloading
                        ? const Color(0xFF38BDF8)
                        : (hasCenter ? const Color(0xFF34D399) : const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dynamicService.statusMessage,
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDownloading ? const Color(0xFF38BDF8) : const Color(0xFFCBD5E1),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              if (isDownloading) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: dynamicService.downloadProgress > 0 ? dynamicService.downloadProgress : null,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: isDownloading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final success = await dynamicService.triggerManualDownload(pipeline);
                              await _refreshDownloadedFiles();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? '50km radius map downloaded and hot-swapped into navigation engine!'
                                        : dynamicService.statusMessage,
                                  ),
                                  backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                      icon: isDownloading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download, size: 16),
                      label: Text(
                        isDownloading ? 'DOWNLOADING...' : 'DOWNLOAD 50KM MAP NOW',
                        style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: isDownloading
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final count = await dynamicService.purgeAllDynamicCache();
                            await _refreshDownloadedFiles();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Purged $count cached dynamic map files.'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: Text(
                      'PURGE CACHE',
                      style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 2: Downloader Form
  Widget _buildDownloaderTab(IdrPipeline pipeline) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1-Tap 300m Micro-Radius Small Streets Downloader Card
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0369A1).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flash_on, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '1-TAP 300M MICRO-GRID DOWNLOAD',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Instantly extracts all small streets, residential lanes, living streets, and service alleys within a 300m radius of your vehicle.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : () => _download300mSmallStreets(pipeline),
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(
                    _isDownloading ? 'DOWNLOADING MICRO-GRID...' : 'DOWNLOAD 300M SMALL STREETS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Presets selector buttons
        Text(
          'QUICK CITY PRESETS',
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              backgroundColor: const Color(0xFF064E3B),
              side: const BorderSide(color: Color(0xFF10B981)),
              label: Text(
                '📍 300m GPS Micro-Radius',
                style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF34D399)),
              ),
              onPressed: () {
                final lat = pipeline.currentLatitude ?? pipeline.sensorService.refLat ?? 18.520;
                final lon = pipeline.currentLongitude ?? pipeline.sensorService.refLon ?? 73.856;
                const dDeg = 0.0027; // ~300 meters
                setState(() {
                  _nameController.text = 'micro_300m_${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}';
                  _southController.text = (lat - dDeg).toStringAsFixed(4);
                  _northController.text = (lat + dDeg).toStringAsFixed(4);
                  _westController.text = (lon - dDeg).toStringAsFixed(4);
                  _eastController.text = (lon + dDeg).toStringAsFixed(4);
                  _selectedLevel = RoadLevel.minorRoads;
                });
              },
            ),
            _quickPresetChip('Pune Urban Grid', 'pune_urban_full', 18.500, 73.810, 18.540, 73.865),
            _quickPresetChip('Mumbai BKC + Express', 'mumbai_bkc', 19.050, 72.850, 19.080, 72.890),
            _quickPresetChip('Thane Urban Center', 'thane_center', 19.180, 72.960, 19.220, 73.000),
            _quickPresetChip('Navi Mumbai Vashi', 'vashi_urban', 19.060, 72.980, 19.090, 73.010),
          ],
        ),

        const SizedBox(height: 10),

        // Auto-fill from Current GPS Location
        OutlinedButton.icon(
          onPressed: () async {
            if (pipeline.currentLatitude != null && pipeline.currentLongitude != null) {
              final lat = pipeline.currentLatitude!;
              final lon = pipeline.currentLongitude!;
              setState(() {
                _nameController.text = 'local_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
                _southController.text = (lat - 0.020).toStringAsFixed(4);
                _northController.text = (lat + 0.020).toStringAsFixed(4);
                _westController.text = (lon - 0.020).toStringAsFixed(4);
                _eastController.text = (lon + 0.020).toStringAsFixed(4);
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Filled bounding box around GPS (${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°)!'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              }
            } else {
              await pipeline.forceRefreshGps();
              if (pipeline.currentLatitude != null && pipeline.currentLongitude != null) {
                final lat = pipeline.currentLatitude!;
                final lon = pipeline.currentLongitude!;
                setState(() {
                  _nameController.text = 'local_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
                  _southController.text = (lat - 0.020).toStringAsFixed(4);
                  _northController.text = (lat + 0.020).toStringAsFixed(4);
                  _westController.text = (lon - 0.020).toStringAsFixed(4);
                  _eastController.text = (lon + 0.020).toStringAsFixed(4);
                });
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(pipeline.gpsStatusMessage ?? 'Searching for GPS location... please wait a moment.'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.my_location, size: 16, color: Color(0xFF10B981)),
          label: Text(
            'USE CURRENT GPS LOCATION (AUTO-FILL BOUNDS)',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF10B981),
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFF064E3B).withValues(alpha: 0.25),
            side: const BorderSide(color: Color(0xFF10B981)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        const SizedBox(height: 16),

        // Map Name Input
        TextField(
          controller: _nameController,
          style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Map Name / Region Identifier',
            labelStyle: GoogleFonts.rajdhani(color: const Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),

        const SizedBox(height: 14),

        // Road Level Selector
        Text(
          'SELECT ROAD DETAIL LEVEL',
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),

        ...RoadLevel.values.map((lvl) {
          final isSelected = _selectedLevel == lvl;
          return InkWell(
            onTap: () => setState(() => _selectedLevel = lvl),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.2) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lvl.label,
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          lvl.description,
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 12),

        // Bounding Box Coordinates
        Text(
          'BOUNDING BOX (WGS84 DEGREES)',
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(child: _coordField('South Lat', _southController)),
            const SizedBox(width: 8),
            Expanded(child: _coordField('West Lon', _westController)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _coordField('North Lat', _northController)),
            const SizedBox(width: 8),
            Expanded(child: _coordField('East Lon', _eastController)),
          ],
        ),

        const SizedBox(height: 16),

        // Error message
        if (_downloadError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Text(
              _downloadError!,
              style: GoogleFonts.rajdhani(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),

        // Progress bar
        if (_isDownloading) ...[
          LinearProgressIndicator(
            value: _downloadProgress,
            backgroundColor: const Color(0xFF1E293B),
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(height: 6),
          Text(
            _downloadStatus,
            textAlign: TextAlign.center,
            style: GoogleFonts.rajdhani(color: const Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],

        // Download Action Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _isDownloading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download, size: 18),
          label: Text(
            _isDownloading ? 'DOWNLOADING ROAD VECTORS...' : 'DOWNLOAD & ACTIVATE OFFLINE',
            style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          onPressed: _isDownloading ? null : () => _startDownload(pipeline),
        ),
      ],
    );
  }

  Widget _quickPresetChip(String label, String name, double s, double w, double n, double e) {
    return ActionChip(
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Color(0xFF334155)),
      label: Text(label, style: GoogleFonts.rajdhani(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFCBD5E1))),
      onPressed: () {
        setState(() {
          _nameController.text = name;
          _southController.text = s.toStringAsFixed(3);
          _westController.text = w.toStringAsFixed(3);
          _northController.text = n.toStringAsFixed(3);
          _eastController.text = e.toStringAsFixed(3);
          _selectedLevel = RoadLevel.minorRoads;
        });
      },
    );
  }

  Widget _coordField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.rajdhani(color: const Color(0xFF94A3B8), fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}
