import 'package:flutter/foundation.dart';

class JsInterceptorService {
  /// Handles the intercepted HTTP/Fetch requests from the WebView.
  Future<void> handleInterceptedRequest({
    required String url,
    required String method,
    dynamic headers,
    dynamic body,
  }) async {
    debugPrint('--- INTERCEPTED JS REQUEST ---');
    debugPrint('URL: $url');
    debugPrint('Method: $method');
    if (headers != null) debugPrint('Headers: $headers');
    if (body != null) debugPrint('Body: $body');
    debugPrint('------------------------------');
  }
}
