import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NearbyGymsPage extends StatefulWidget {
  const NearbyGymsPage({super.key});

  @override
  State<NearbyGymsPage> createState() => _NearbyGymsPageState();
}

class _NearbyGymsPageState extends State<NearbyGymsPage> {
  static const int _radiusMeters = 8000;
  static final List<Uri> _overpassEndpoints = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.kumi.systems/api/interpreter'),
  ];
  static const Map<String, String> _overpassHeaders = {
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    'Accept': 'application/json',
    'User-Agent': 'FitNetFitnessApp/1.0',
  };
  static const Set<int> _retryableOverpassStatuses = {
    406,
    429,
    500,
    502,
    503,
    504,
  };

  bool _isLoading = true;
  String? _errorMessage;
  _NearbyGymsErrorAction? _errorAction;
  Position? _position;
  List<_NearbyGym> _gyms = const [];
  bool _searchCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadNearbyGyms();
  }

  Future<void> _loadNearbyGyms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorAction = null;
      _position = null;
      _gyms = const [];
      _searchCompleted = false;
    });

    try {
      final position = await _getCurrentPosition();
      _position = position;
      final gyms = await _searchNearbyGyms(position);

      if (!mounted) return;
      setState(() {
        _position = position;
        _gyms = gyms;
        _searchCompleted = true;
        _isLoading = false;
      });
    } on _NearbyGymsException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _errorAction = error.action;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Nearby gyms could not be loaded. Check your internet connection and try again.';
        _errorAction = null;
        _isLoading = false;
      });
    }
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const _NearbyGymsException(
        'Location services are turned off. Enable location to find gyms near you.',
        action: _NearbyGymsErrorAction.locationSettings,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const _NearbyGymsException(
        'Location permission is needed to find nearby gyms.',
        action: _NearbyGymsErrorAction.appSettings,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const _NearbyGymsException(
        'Location permission is permanently denied. Enable it from app settings, then retry.',
        action: _NearbyGymsErrorAction.appSettings,
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw const _NearbyGymsException(
        'Your location could not be detected. Move somewhere with a clearer signal and try again.',
      );
    }
  }

  Future<List<_NearbyGym>> _searchNearbyGyms(Position position) async {
    final query = _buildOverpassQuery(position);
    var hadNetworkFailure = false;
    var hadServiceFailure = false;

    for (final endpoint in _overpassEndpoints) {
      try {
        final response = await http
            .post(endpoint, headers: _overpassHeaders, body: {'data': query})
            .timeout(const Duration(seconds: 30));

        _debugLogOverpassResponse(
          endpoint: endpoint,
          statusCode: response.statusCode,
          responseBody: response.body,
          query: query,
        );

        if (response.statusCode == 200) {
          return _parseNearbyGyms(response.body, position);
        }

        if (_retryableOverpassStatuses.contains(response.statusCode)) {
          hadServiceFailure = true;
          continue;
        }

        throw const _NearbyGymsException(
          'Nearby gym search is temporarily unavailable. You can still open Google Maps.',
        );
      } on TimeoutException catch (error) {
        _debugLogOverpassFailure(
          endpoint: endpoint,
          error: error,
          query: query,
        );
        hadServiceFailure = true;
        continue;
      } on http.ClientException catch (error) {
        _debugLogOverpassFailure(
          endpoint: endpoint,
          error: error,
          query: query,
        );
        hadNetworkFailure = true;
        continue;
      } on FormatException catch (error) {
        _debugLogOverpassFailure(
          endpoint: endpoint,
          error: error,
          query: query,
        );
        throw const _NearbyGymsException(
          'Nearby gym search is temporarily unavailable. You can still open Google Maps.',
        );
      }
    }

    if (hadNetworkFailure && !hadServiceFailure) {
      throw const _NearbyGymsException(
        'Network is unavailable. Check your internet connection and try again.',
      );
    }

    throw const _NearbyGymsException(
      'Nearby gym search is temporarily unavailable. You can still open Google Maps.',
    );
  }

  String _buildOverpassQuery(Position position) {
    final lat = position.latitude.toStringAsFixed(7);
    final lon = position.longitude.toStringAsFixed(7);
    return '''
[out:json][timeout:25];
(
node["leisure"="fitness_centre"](around:$_radiusMeters,$lat,$lon);
way["leisure"="fitness_centre"](around:$_radiusMeters,$lat,$lon);
relation["leisure"="fitness_centre"](around:$_radiusMeters,$lat,$lon);
node["leisure"="sports_centre"](around:$_radiusMeters,$lat,$lon);
way["leisure"="sports_centre"](around:$_radiusMeters,$lat,$lon);
relation["leisure"="sports_centre"](around:$_radiusMeters,$lat,$lon);
node["amenity"="gym"](around:$_radiusMeters,$lat,$lon);
way["amenity"="gym"](around:$_radiusMeters,$lat,$lon);
relation["amenity"="gym"](around:$_radiusMeters,$lat,$lon);
node["sport"="fitness"](around:$_radiusMeters,$lat,$lon);
way["sport"="fitness"](around:$_radiusMeters,$lat,$lon);
relation["sport"="fitness"](around:$_radiusMeters,$lat,$lon);
);
out center tags 50;
''';
  }

  List<_NearbyGym> _parseNearbyGyms(String responseBody, Position position) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const _NearbyGymsException(
        'Nearby gym search is temporarily unavailable. You can still open Google Maps.',
      );
    }

    final elements = decoded['elements'];
    if (elements is! List) {
      throw const _NearbyGymsException(
        'Nearby gym search is temporarily unavailable. You can still open Google Maps.',
      );
    }

    final gymsByKey = <String, _NearbyGym>{};
    for (final element in elements.whereType<Map<String, dynamic>>()) {
      final gym = _NearbyGym.fromOverpass(element, position);
      if (gym != null) {
        gymsByKey['${gym.latitude},${gym.longitude},${gym.name}'] = gym;
      }
    }

    final gyms = gymsByKey.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return gyms;
  }

  void _debugLogOverpassResponse({
    required Uri endpoint,
    required int statusCode,
    required String responseBody,
    required String query,
  }) {
    if (!kDebugMode) return;
    debugPrint('NearbyGyms Overpass endpoint: $endpoint');
    debugPrint('NearbyGyms Overpass method: POST');
    debugPrint('NearbyGyms Overpass status: $statusCode');
    debugPrint(
      'NearbyGyms Overpass response body: ${_firstDebugChars(responseBody)}',
    );
    debugPrint('NearbyGyms Overpass query: ${_sanitizeDebugQuery(query)}');
  }

  void _debugLogOverpassFailure({
    required Uri endpoint,
    required Object error,
    required String query,
  }) {
    if (!kDebugMode) return;
    debugPrint('NearbyGyms Overpass endpoint: $endpoint');
    debugPrint('NearbyGyms Overpass method: POST');
    debugPrint('NearbyGyms Overpass status: request failed');
    debugPrint('NearbyGyms Overpass response body: ${error.toString()}');
    debugPrint('NearbyGyms Overpass query: ${_sanitizeDebugQuery(query)}');
  }

  String _firstDebugChars(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 500) return normalized;
    return normalized.substring(0, 500);
  }

  String _sanitizeDebugQuery(String query) {
    return query.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _openErrorAction() async {
    switch (_errorAction) {
      case _NearbyGymsErrorAction.appSettings:
        await Geolocator.openAppSettings();
        return;
      case _NearbyGymsErrorAction.locationSettings:
        await Geolocator.openLocationSettings();
        return;
      case null:
        return;
    }
  }

  Future<void> _openSearchInGoogleMaps() async {
    final position = _position;
    if (position == null) {
      await _loadNearbyGyms();
      return;
    }
    await _launchMaps(
      Uri.parse(
        'https://www.google.com/maps/search/gyms/'
        '@${position.latitude},${position.longitude},14z',
      ),
    );
  }

  Future<void> _openDirections(_NearbyGym gym) {
    return _launchMaps(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${gym.latitude},${gym.longitude}',
        'travelmode': 'driving',
      }),
    );
  }

  Future<void> _launchMaps(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Gyms'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadNearbyGyms,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _LoadingState(message: 'Finding gyms near you...');
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _ErrorState(
        message: errorMessage,
        action: _errorAction,
        onRetry: _loadNearbyGyms,
        onOpenAction: _errorAction == null ? null : _openErrorAction,
        onOpenMaps: _position == null ? null : _openSearchInGoogleMaps,
      );
    }

    if (_searchCompleted && _gyms.isEmpty) {
      return _NoResultsState(
        radiusMeters: _radiusMeters,
        onRefresh: _loadNearbyGyms,
        onOpenMaps: _position == null ? null : _openSearchInGoogleMaps,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNearbyGyms,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _gyms.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SearchSummary(
              count: _gyms.length,
              radiusMeters: _radiusMeters,
              onOpenMaps: _openSearchInGoogleMaps,
            );
          }

          final gym = _gyms[index - 1];
          return _GymCard(gym: gym, onDirections: () => _openDirections(gym));
        },
      ),
    );
  }
}

class _NearbyGym {
  const _NearbyGym({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.category,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String category;

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  static _NearbyGym? fromOverpass(
    Map<String, dynamic> element,
    Position position,
  ) {
    final center = element['center'] is Map<String, dynamic>
        ? element['center'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final lat = _readDouble(element['lat']) ?? _readDouble(center['lat']);
    final lon = _readDouble(element['lon']) ?? _readDouble(center['lon']);
    if (lat == null || lon == null) return null;

    final tags = element['tags'] is Map<String, dynamic>
        ? element['tags'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final name = (tags['name'] as String?)?.trim();
    final category = _categoryFromTags(tags);

    return _NearbyGym(
      name: name == null || name.isEmpty ? category : name,
      latitude: lat,
      longitude: lon,
      distanceMeters: _distanceMeters(
        position.latitude,
        position.longitude,
        lat,
        lon,
      ),
      category: category,
    );
  }

  static String _categoryFromTags(Map<String, dynamic> tags) {
    if (tags['leisure'] == 'fitness_centre') return 'Fitness centre';
    if (tags['leisure'] == 'sports_centre') return 'Sports centre';
    if (tags['amenity'] == 'gym') return 'Gym';
    if (tags['sport'] == 'fitness') return 'Fitness';
    return 'Gym or fitness center';
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _distanceMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(endLatitude - startLatitude);
    final dLon = _degreesToRadians(endLongitude - startLongitude);
    final lat1 = _degreesToRadians(startLatitude);
    final lat2 = _degreesToRadians(endLatitude);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) => degrees * pi / 180;
}

class _NearbyGymsException implements Exception {
  const _NearbyGymsException(this.message, {this.action});

  final String message;
  final _NearbyGymsErrorAction? action;
}

enum _NearbyGymsErrorAction { appSettings, locationSettings }

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.action,
    required this.onRetry,
    required this.onOpenAction,
    required this.onOpenMaps,
  });

  final String message;
  final _NearbyGymsErrorAction? action;
  final VoidCallback onRetry;
  final VoidCallback? onOpenAction;
  final VoidCallback? onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final actionLabel = switch (action) {
      _NearbyGymsErrorAction.appSettings => 'Open App Settings',
      _NearbyGymsErrorAction.locationSettings => 'Open Location Settings',
      null => null,
    };

    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  if (actionLabel != null)
                    FilledButton.icon(
                      onPressed: onOpenAction,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(actionLabel),
                    ),
                  if (onOpenMaps != null)
                    FilledButton.icon(
                      onPressed: onOpenMaps,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open in Google Maps'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({
    required this.radiusMeters,
    required this.onRefresh,
    required this.onOpenMaps,
  });

  final int radiusMeters;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenMaps;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'No nearby gyms found within ${(radiusMeters / 1000).round()} km.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              const Text(
                'The search completed successfully, but OpenStreetMap did not return any gym results for this area.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Google Maps'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.count,
    required this.radiusMeters,
    required this.onOpenMaps,
  });

  final int count;
  final int radiusMeters;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.place_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count gyms and fitness centers found within ${(radiusMeters / 1000).round()} km.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onOpenMaps,
              tooltip: 'Open in Google Maps',
              icon: const Icon(Icons.map_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _GymCard extends StatelessWidget {
  const _GymCard({required this.gym, required this.onDirections});

  final _NearbyGym gym;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.fitness_center)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gym.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${gym.category} - ${gym.distanceLabel} away'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onDirections,
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Directions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
