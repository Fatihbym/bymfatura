import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final StreamController<Uri> _uriController = StreamController<Uri>.broadcast();

  Stream<Uri> get uriStream => _uriController.stream;

  Future<void> init() async {
    _appLinks = AppLinks();

    // Check initial link if app was in cold state (terminated)
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('Initial Deep Link: $initialUri');
        _uriController.sink.add(initialUri);
      }
    } catch (e) {
      debugPrint('Failed to get initial uri: $e');
    }

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        debugPrint('Received Deep Link: $uri');
        _uriController.sink.add(uri);
      }
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
    _uriController.close();
  }
}
