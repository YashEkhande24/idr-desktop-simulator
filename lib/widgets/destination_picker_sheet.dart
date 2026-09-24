import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../core/math_utils.dart';
import '../models/navigation_models.dart';
import '../services/idr_pipeline.dart';
import '../services/routing_service.dart';

/// Interactive modal sheet to search, choose landmarks, or enter coordinates to navigate to.
class DestinationPickerSheet extends StatefulWidget {
  final IdrPipeline pipeline;
  final NavDestination? initialDestination;

  const DestinationPickerSheet({
    super.key,
    required this.pipeline,
    this.initialDestination,
  });

  @override
  State<DestinationPickerSheet> createState() => _DestinationPickerSheetState();
}

class _DestinationPickerSheetState extends State<DestinationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  NavDestination? _selectedDestination;
  bool _isCalculatingRoute = false;
  NavRoute? _previewRoute;
  String? _errorMessage;
  
  Timer? _debounce;
  bool _isSearchingLive = false;
  List<NavDestination> _liveResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) {
      _selectedDestination = widget.initialDestination;
      _searchController.text = widget.initialDestination!.name;
      _latController.text = widget.initialDestination!.latitude?.toStringAsFixed(5) ?? '';
      _lonController.text = widget.initialDestination!.longitude?.toStringAsFixed(5) ?? '';
      _isCalculatingRoute = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectDestination(widget.initialDestination!);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.length < 3) {
      setState(() {
        _liveResults.clear();
        _isSearchingLive = false;
      });
      return;
    }

    setState(() {
      _isSearchingLive = true;
    });

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5');
      try {
        final response = await http.get(url, headers: {'User-Agent': 'com.idr.navigator'});
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          final results = data.map((item) {
            final lat = double.tryParse(item['lat'].toString()) ?? 0.0;
            final lon = double.tryParse(item['lon'].toString()) ?? 0.0;
            final refLat = widget.pipeline.sensorService.refLat ?? lat;
            final refLon = widget.pipeline.sensorService.refLon ?? lon;
            return NavDestination(
              name: item['display_name'].toString().split(',').first,
              subtitle: item['display_name'].toString(),
              targetEnu: MathUtils.wgs84ToEnu(lat: lat, lon: lon, refLat: refLat, refLon: refLon),
              latitude: lat,
              longitude: lon,
            );
          }).toList();
          
          if (mounted) {
            setState(() {
              _liveResults = results;
              _isSearchingLive = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearchingLive = false;
          });
        }
      }
    });
  }

  Future<void> _selectDestination(NavDestination dest) async {
    final refLat = widget.pipeline.sensorService.refLat;
    final refLon = widget.pipeline.sensorService.refLon;

    NavDestination effectiveDest = dest;
    if (dest.latitude != null && dest.longitude != null && refLat != null && refLon != null) {
      effectiveDest = NavDestination(
        name: dest.name,
        subtitle: dest.subtitle,
        targetEnu: MathUtils.wgs84ToEnu(lat: dest.latitude!, lon: dest.longitude!, refLat: refLat, refLon: refLon),
        latitude: dest.latitude,
        longitude: dest.longitude,
        isCustomPin: dest.isCustomPin,
      );
    }

    if (mounted) {
      setState(() {
        _selectedDestination = effectiveDest;
        _searchController.text = effectiveDest.name;
        _latController.text = effectiveDest.latitude?.toStringAsFixed(5) ?? '';
        _lonController.text = effectiveDest.longitude?.toStringAsFixed(5) ?? '';
        _isCalculatingRoute = true;
        _errorMessage = null;
      });
    }

    final vehiclePos = widget.pipeline.latestSolution?.idrState.position ?? Vec3.zero;

    try {
      final route = await RoutingService.calculateRoute(
        originEnu: vehiclePos,
        destination: effectiveDest,
        roadBranches: widget.pipeline.mapSnapper.branches,
        refLat: widget.pipeline.sensorService.refLat,
        refLon: widget.pipeline.sensorService.refLon,
        originLat: widget.pipeline.currentLatitude,
        originLon: widget.pipeline.currentLongitude,
      );

      if (mounted) {
        setState(() {
          _previewRoute = route;
          _isCalculatingRoute = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCalculatingRoute = false;
          _errorMessage = 'Could not compute path: $e';
        });
      }
    }
  }

  void _onCoordinateSubmit() {
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());

    if (lat == null || lon == null) {
      setState(() => _errorMessage = 'Please enter valid numbers for Latitude and Longitude');
      return;
    }

    final refLat = widget.pipeline.sensorService.refLat ?? lat;
    final refLon = widget.pipeline.sensorService.refLon ?? lon;
    final targetEnu = MathUtils.wgs84ToEnu(lat: lat, lon: lon, refLat: refLat, refLon: refLon);

    final dest = NavDestination(
      name: 'Custom Coordinates (${lat.toStringAsFixed(3)}°, ${lon.toStringAsFixed(3)}°)',
      subtitle: 'Manual Geodetic Target',
      targetEnu: targetEnu,
      latitude: lat,
      longitude: lon,
      isCustomPin: true,
    );

    _selectDestination(dest);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    
    // Merge live results with local POIs
    final List<NavDestination> filteredPOIs = [];
    if (_liveResults.isNotEmpty) {
      filteredPOIs.addAll(_liveResults);
    }
    
    filteredPOIs.addAll(RoutingService.standardPOIs.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) || (p.subtitle?.toLowerCase().contains(query) ?? false);
    }));

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.navigation, color: Color(0xFF38BDF8), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHERE TO?',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Select landmark or enter target coordinates',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
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

          const Divider(color: Color(0xFF1E293B), height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Search Input Field
                TextField(
                  controller: _searchController,
                  style: GoogleFonts.rajdhani(color: Colors.white, fontWeight: FontWeight.w700),
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search city landmark, highway, or POI...',
                    hintStyle: GoogleFonts.rajdhani(color: const Color(0xFF64748B)),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),

                const SizedBox(height: 16),

                // Selected Destination / Route Preview Card
                if (_selectedDestination != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDestination!.name,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedDestination!.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _selectedDestination!.subtitle!,
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),

                        if (_isCalculatingRoute) ...[
                          const Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8))),
                              SizedBox(width: 10),
                              Text('Calculating optimal vector road path...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            ],
                          ),
                        ] else if (_previewRoute != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMetricItem(
                                label: 'DISTANCE',
                                value: '${_previewRoute!.totalDistanceKm.toStringAsFixed(1)} km',
                                icon: Icons.straighten,
                                color: const Color(0xFF38BDF8),
                              ),
                              _buildMetricItem(
                                label: 'EST. TIME',
                                value: '${_previewRoute!.estimatedDurationMinutes} min',
                                icon: Icons.timer,
                                color: const Color(0xFF34D399),
                              ),
                              _buildMetricItem(
                                label: 'ROUTING',
                                value: _previewRoute!.isOfflineAStar ? '100% OFFLINE A*' : 'OSRM HIGHWAY',
                                icon: _previewRoute!.isOfflineAStar ? Icons.lan : Icons.cloud,
                                color: const Color(0xFFF59E0B),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Big Start Navigation Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                widget.pipeline.navigationService.startNavigation(_selectedDestination!, widget.pipeline);
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Navigating to ${_selectedDestination!.name}!'),
                                    backgroundColor: const Color(0xFF10B981),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.navigation, size: 20, color: Colors.black),
                              label: Text(
                                'START TURN-BY-TURN GUIDANCE',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.rajdhani(color: const Color(0xFFEF4444), fontWeight: FontWeight.w700),
                    ),
                  ),

                // Popular POI List Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _liveResults.isNotEmpty ? 'LIVE SEARCH RESULTS' : 'POPULAR REGIONAL DESTINATIONS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    if (_isSearchingLive)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                ...filteredPOIs.map((poi) {
                  final isSelected = _selectedDestination?.name == poi.name;
                  return Card(
                    color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.place, color: Color(0xFF38BDF8), size: 18),
                      ),
                      title: Text(
                        poi.name,
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        poi.subtitle ?? '',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF64748B)),
                      onTap: () => _selectDestination(poi),
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // Manual Coordinates Expansion Tile
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.my_location, color: Color(0xFF34D399), size: 20),
                    title: Text(
                      'CUSTOM GEODETIC COORDINATES',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFE2E8F0),
                        letterSpacing: 0.8,
                      ),
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _latController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Latitude (°)',
                                      labelStyle: GoogleFonts.rajdhani(color: const Color(0xFF94A3B8)),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _lonController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Longitude (°)',
                                      labelStyle: GoogleFonts.rajdhani(color: const Color(0xFF94A3B8)),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _onCoordinateSubmit,
                                icon: const Icon(Icons.route, size: 16),
                                label: Text(
                                  'SET COORDINATE TARGET',
                                  style: GoogleFonts.rajdhani(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
