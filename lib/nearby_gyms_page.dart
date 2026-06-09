import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NearbyGymsPage extends StatefulWidget {
  const NearbyGymsPage({super.key});

  @override
  State<NearbyGymsPage> createState() => _NearbyGymsPageState();
}

class _NearbyGymsPageState extends State<NearbyGymsPage> {
  WebViewController? _controller;
  bool _isLoadingLocation = true;
  bool _isLoadingMap = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNearbyGyms();
  }

  Future<void> _loadNearbyGyms() async {
    setState(() {
      _isLoadingLocation = true;
      _isLoadingMap = false;
      _errorMessage = null;
      _controller = null;
    });

    try {
      final position = await _getCurrentPosition();
      final uri = Uri.parse(
        'https://www.google.com/maps/search/gyms/'
        '@${position.latitude},${position.longitude},14z',
      );

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _isLoadingMap = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoadingMap = false);
            },
            onWebResourceError: (error) {
              if (!mounted || error.isForMainFrame == false) return;
              setState(() {
                _isLoadingMap = false;
                _errorMessage =
                    'Could not load the gyms map. Check your connection and try again.';
              });
            },
          ),
        )
        ..loadRequest(uri);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isLoadingLocation = false;
        _isLoadingMap = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _isLoadingMap = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const _NearbyGymsException(
        'Location services are turned off. Please enable location and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const _NearbyGymsException(
        'Location permission is required to find nearby gyms.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const _NearbyGymsException(
        'Location permission is permanently denied. Enable it from Android settings, then retry.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Gyms')),
      body: Stack(
        children: [
          if (_controller != null && _errorMessage == null)
            WebViewWidget(controller: _controller!)
          else if (_errorMessage != null)
            _ErrorState(message: _errorMessage!, onRetry: _loadNearbyGyms)
          else
            const _LoadingState(message: 'Finding gyms near you...'),
          if (_isLoadingMap)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          if (_isLoadingLocation && _errorMessage == null)
            const _LoadingState(message: 'Getting your location...'),
        ],
      ),
    );
  }
}

class _NearbyGymsException implements Exception {
  const _NearbyGymsException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
              const Icon(Icons.location_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
