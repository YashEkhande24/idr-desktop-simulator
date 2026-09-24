import 'package:flutter/foundation.dart';
import '../core/math_utils.dart';
import 'idr_pipeline.dart';
import 'osm_download_service.dart';

/// Dynamic Map Engine with 50 km Radius & 25 km Buffer Trigger.
///
/// Implements autonomous geospatial tile lifecycle:
/// 1. 50 km Radius Detailed Map: Downloads road network centered on current vehicle GPS position.
/// 2. 25 km Buffer Threshold: Monitors vehicle distance from active map center. When displacement >= 25 km,
///    triggers background download of the next 50 km tile ahead.
/// 3. Seamless Hot-Swap: Automatically loads the new tile into MapSnapper without jumping coordinates.
/// 4. Dynamic Deletion: Prunes older cached tiles from storage, preventing disk bloat.
class DynamicMapService extends ChangeNotifier {
  double _radiusKm = 50.0;
  double _bufferKm = 25.0;
  bool _isAutoDynamicEnabled = true;

  double? _activeCenterLat;
  double? _activeCenterLon;
  double _distanceMovedSinceCenterKm = 0.0;

  bool _isDownloading = false;
  String _statusMessage = 'Idle (50km Radius / 25km Buffer)';
  double _downloadProgress = 0.0;
  DateTime? _lastDownloadTime;
  String? _currentDynamicMapPath;

  double get radiusKm => _radiusKm;
  double get bufferKm => _bufferKm;
  bool get isAutoDynamicEnabled => _isAutoDynamicEnabled;

  double? get activeCenterLat => _activeCenterLat;
  double? get activeCenterLon => _activeCenterLon;
  double get distanceMovedSinceCenterKm => _distanceMovedSinceCenterKm;

  double get remainingBufferDistanceKm {
    final remaining = _bufferKm - _distanceMovedSinceCenterKm;
    return remaining < 0.0 ? 0.0 : remaining;
  }

  bool get isDownloading => _isDownloading;
  String get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;
  DateTime? get lastDownloadTime => _lastDownloadTime;
  String? get currentDynamicMapPath => _currentDynamicMapPath;

  void setAutoDynamicEnabled(bool enabled) {
    _isAutoDynamicEnabled = enabled;
    notifyListeners();
  }

  void setRadiusKm(double radius) {
    if (radius >= 0.3 && radius <= 100.0) {
      _radiusKm = radius;
      notifyListeners();
    }
  }

  void setBufferKm(double buffer) {
    if (buffer >= 5.0 && buffer <= 50.0) {
      _bufferKm = buffer;
      notifyListeners();
    }
  }

  void reset() {
    _activeCenterLat = null;
    _activeCenterLon = null;
    _distanceMovedSinceCenterKm = 0.0;
    _isDownloading = false;
    _statusMessage = 'Idle (50km Radius / 25km Buffer)';
    notifyListeners();
  }


  /// Evaluates vehicle GPS position against the active 50 km map center.
  /// If displacement >= 25 km buffer threshold, automatically triggers background download.
  Future<void> onLocationUpdate(double lat, double lon, IdrPipeline pipeline) async {
    if (!_isAutoDynamicEnabled) return;

    if (_activeCenterLat == null || _activeCenterLon == null) {
      // First fix: automatically trigger initial 50 km radius map download
      await trigger50KmDownload(lat, lon, pipeline);
      return;
    }

    final distMeters = MathUtils.haversineDistanceMeters(_activeCenterLat!, _activeCenterLon!, lat, lon);
    _distanceMovedSinceCenterKm = distMeters / 1000.0;

    if (_distanceMovedSinceCenterKm >= _bufferKm && !_isDownloading) {
      debugPrint('[DynamicMapService] 25 km buffer reached (${_distanceMovedSinceCenterKm.toStringAsFixed(1)} km from center). Triggering dynamic download...');
      await trigger50KmDownload(lat, lon, pipeline);
    } else {
      notifyListeners();
    }
  }

  /// Downloads a 50 km radius detailed map around (lat, lon) and hot-swaps it into the pipeline.
  Future<bool> trigger50KmDownload(double lat, double lon, IdrPipeline pipeline) async {
    if (_isDownloading) return false;

    _isDownloading = true;
    _statusMessage = 'Preparing 50km radius download...';
    _downloadProgress = 0.05;
    notifyListeners();

    try {
      final latStr = lat.toStringAsFixed(2).replaceAll('.', '_');
      final lonStr = lon.toStringAsFixed(2).replaceAll('.', '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final mapName = 'dynamic_tile_${latStr}_${lonStr}_$timestamp';

      final file = await OsmDownloadService.downloadRadiusArea(
        mapName: mapName,
        centerLat: lat,
        centerLon: lon,
        radiusKm: _radiusKm,
        level: RoadLevel.arterials,
        onProgress: (status, progress) {
          _statusMessage = status;
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      _statusMessage = 'Activating road network in navigation engine...';
      notifyListeners();

      // Hot-swap into pipeline keeping existing global ENU anchor continuity
      final refLat = pipeline.sensorService.refLat ?? lat;
      final refLon = pipeline.sensorService.refLon ?? lon;
      final refAlt = pipeline.sensorService.refAlt ?? 0.0;

      await pipeline.loadOfflineOsmMapFromFile(
        file,
        mapName: '50km Grid (${lat.toStringAsFixed(2)}°, ${lon.toStringAsFixed(2)}°)',
        anchorLat: refLat,
        anchorLon: refLon,
        anchorAlt: refAlt,
      );

      _activeCenterLat = lat;
      _activeCenterLon = lon;
      _distanceMovedSinceCenterKm = 0.0;
      _currentDynamicMapPath = file.path;
      _lastDownloadTime = DateTime.now();
      _statusMessage = 'Active 50km map (${pipeline.activeRoadBranchCount} roads)';
      _isDownloading = false;
      _downloadProgress = 1.0;

      // Dynamic Deletion: Prune older dynamic tiles from storage
      final pruned = await OsmDownloadService.pruneDynamicCache(keepFilePath: file.path, maxFilesToKeep: 2);
      debugPrint('[DynamicMapService] Pruned $pruned old dynamic map files from disk.');

      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = 'Download note: ${e.toString().replaceAll('Exception: ', '')}';
      _isDownloading = false;
      debugPrint('[DynamicMapService] Error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Manual trigger using the current location
  Future<bool> triggerManualDownload(IdrPipeline pipeline) async {
    final lat = pipeline.currentLatitude;
    final lon = pipeline.currentLongitude;
    if (lat != null && lon != null) {
      return await trigger50KmDownload(lat, lon, pipeline);
    } else {
      _statusMessage = 'GPS location required for 50km map download';
      notifyListeners();
      return false;
    }
  }

  /// Downloads a local grid of small streets (residential, service, alleys) around current vehicle position.
  /// Defaults to 1.0 km radius (covers ~3.14 sq km of neighbourhood streets).
  Future<bool> triggerLocalSmallStreetsDownload(IdrPipeline pipeline, {double radiusKm = 1.0}) async {
    final lat = pipeline.currentLatitude ?? pipeline.sensorService.refLat;
    final lon = pipeline.currentLongitude ?? pipeline.sensorService.refLon;
    if (lat == null || lon == null) {
      _statusMessage = 'GPS location required for small streets download';
      notifyListeners();
      return false;
    }

    if (_isDownloading) return false;

    _isDownloading = true;
    final radiusLabel = radiusKm < 1.0 ? '${(radiusKm * 1000).round()}m' : '${radiusKm.toStringAsFixed(radiusKm % 1 == 0 ? 0 : 1)}km';
    _statusMessage = 'Downloading $radiusLabel small street grid...';
    _downloadProgress = 0.1;
    notifyListeners();

    try {
      final latStr = lat.toStringAsFixed(3).replaceAll('.', '_');
      final lonStr = lon.toStringAsFixed(3).replaceAll('.', '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final mapName = 'streets_${radiusLabel}_${latStr}_${lonStr}_$timestamp';

      final file = await OsmDownloadService.downloadRadiusArea(
        mapName: mapName,
        centerLat: lat,
        centerLon: lon,
        radiusKm: radiusKm,
        level: RoadLevel.minorRoads, // Includes residential, service lanes, living streets, alleys
        onProgress: (status, progress) {
          _statusMessage = status;
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      final refLat = pipeline.sensorService.refLat ?? lat;
      final refLon = pipeline.sensorService.refLon ?? lon;
      final refAlt = pipeline.sensorService.refAlt ?? 0.0;

      await pipeline.loadOfflineOsmMapFromFile(
        file,
        mapName: '$radiusLabel Small Streets (${lat.toStringAsFixed(3)}°, ${lon.toStringAsFixed(3)}°)',
        anchorLat: refLat,
        anchorLon: refLon,
        anchorAlt: refAlt,
      );

      _activeCenterLat = lat;
      _activeCenterLon = lon;
      _distanceMovedSinceCenterKm = 0.0;
      _currentDynamicMapPath = file.path;
      _lastDownloadTime = DateTime.now();
      _statusMessage = 'Active $radiusLabel small streets (${pipeline.activeRoadBranchCount} roads)';
      _isDownloading = false;
      _downloadProgress = 1.0;

      await OsmDownloadService.pruneDynamicCache(keepFilePath: file.path, maxFilesToKeep: 4);

      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = 'Download note: ${e.toString().replaceAll('Exception: ', '')}';
      _isDownloading = false;
      notifyListeners();
      return false;
    }
  }

  /// Downloads a 1 km radius grid of small streets (primary recommendation).
  Future<bool> trigger1KmSmallStreetsDownload(IdrPipeline pipeline) =>
      triggerLocalSmallStreetsDownload(pipeline, radiusKm: 1.0);

  /// Downloads a 300m micro-grid of small streets.
  Future<bool> trigger300mSmallStreetsDownload(IdrPipeline pipeline) =>
      triggerLocalSmallStreetsDownload(pipeline, radiusKm: 0.3);

  /// Purge all dynamic cached tiles from storage
  Future<int> purgeAllDynamicCache() async {
    final count = await OsmDownloadService.purgeAllDynamicMaps();
    _currentDynamicMapPath = null;
    _activeCenterLat = null;
    _activeCenterLon = null;
    _distanceMovedSinceCenterKm = 0.0;
    _statusMessage = 'Purged $count cached dynamic map files';
    notifyListeners();
    return count;
  }
}
