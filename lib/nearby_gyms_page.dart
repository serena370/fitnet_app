import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
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
  Uri? _mapsUri;

  @override
  void initState() {
    super.initState();
    _loadNearbyGyms();
  }

  Future<void> _loadNearbyGyms() async {
    if (!mounted) return;
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
      _mapsUri = uri;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setUserAgent("Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _isLoadingMap = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoadingMap = false);
            },
            onWebResourceError: (error) {
              if (!mounted || error.isForMainFrame != true) return;
              // Ignore some common harmless errors
              if (error.description.contains('net::ERR_CACHE_MISS') || 
                  error.description.contains('net::ERR_CONNECTION_REFUSED')) {
                return;
              }
              setState(() {
                _isLoadingMap = false;
                _errorMessage =
                'The in-app map encountered an error. You can open it in Google Maps instead.';
              });
            },
            onNavigationRequest: (NavigationRequest request) async {
              final url = request.url;
              if (url.startsWith('http://') || url.startsWith('https://')) {
                return NavigationDecision.navigate;
              }
              
              // Handle non-web schemes (intent://, geo:, comgooglemaps:, etc)
              try {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                debugPrint('Could not launch custom scheme: $e');
              }
              return NavigationDecision.prevent;
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
        _errorMessage = error is _NearbyGymsException
            ? error.toString()
            : 'The in-app map could not load. Please check your internet or use Google Maps.';
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

  Future<void> _openInGoogleMaps() async {
    final uri = _mapsUri;
    if (uri == null) {
      await _loadNearbyGyms();
      return;
    }

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
          if (_mapsUri != null)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              onPressed: _openInGoogleMaps,
              tooltip: 'Open in Google Maps',
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null && _errorMessage == null)
            WebViewWidget(controller: _controller!)
          else if (_errorMessage != null)
            _ErrorState(
              message: _errorMessage!,
              onRetry: _loadNearbyGyms,
              onOpenMaps: _mapsUri == null ? null : _openInGoogleMaps,
            )
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
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.onOpenMaps,
  });

  final String message;
  final VoidCallback onRetry;
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
              const Icon(Icons.location_off_outlined, size: 56, color: Colors.grey),
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