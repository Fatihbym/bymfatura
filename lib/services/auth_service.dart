import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final String baseUrl = 'https://bymfatura.com';
  final String loginUrl = 'https://bymfatura.com/accounting/login';
  final String dashboardUrl = 'https://bymfatura.com/accounting/';

  // Dynamic User-Agent (Web görünümü ve platform ile 100% eşleşen User-Agent)
  String _customUserAgent = kIsWeb
      ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
      : (defaultTargetPlatform == TargetPlatform.iOS
          ? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
          : "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36");

  String get customUserAgent => _customUserAgent;

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionCookie;
  String? _idToken;
  String? _userDataRaw;

  String? get sessionCookie => _sessionCookie;
  String? get idToken => _idToken;
  String? get userDataRaw => _userDataRaw;

  /// High-Speed Native Direct Authentication
  /// Authenticates natively via /accounting/api/auth/signin, gets token and fetches /user/me
  Future<bool> loginAPI(String email, String password, {bool rememberMe = true}) async {
    try {
      final signinUrl = Uri.parse('$baseUrl/accounting/api/auth/signin');
      final headers = <String, String>{
        'Content-Type': 'application/json;charset=UTF-8',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'User-Agent': customUserAgent,
        'Origin': baseUrl,
        'Referer': loginUrl,
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };

      final response = await http.post(
        signinUrl,
        headers: headers,
        body: jsonEncode({
          "username": email,
          "password": password,
          "rememberMe": rememberMe,
        }),
      ).timeout(const Duration(seconds: 7));

      final cookies = response.headers['set-cookie'];
      if (cookies != null && cookies.isNotEmpty) {
        _sessionCookie = cookies;
        _saveCookie(cookies);
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        String? tokenStr;

        if (data['token'] is Map) {
          tokenStr = data['token']['accessToken'] ?? data['token']['idToken'] ?? data['token']['jwt'];
        } else {
          tokenStr = data['idToken'] ?? data['token'] ?? data['id_token'] ?? data['accessToken'] ?? data['jwt'];
        }

        if (tokenStr != null && tokenStr.isNotEmpty) {
          _idToken = tokenStr;
          
          // Save token to shared preferences for instant persistent auto-login
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('id_token', tokenStr);

          // Fetch user profile context from /accounting/api/user/me
          try {
            final userMeUrl = Uri.parse('$baseUrl/accounting/api/user/me');
            final userMeHeaders = <String, String>{
              'Accept': 'application/json, text/plain, */*',
              'Authorization': 'Bearer $tokenStr',
              'User-Agent': customUserAgent,
              'Referer': dashboardUrl,
            };

            final userMeResponse = await http.get(userMeUrl, headers: userMeHeaders).timeout(const Duration(seconds: 5));
            if (userMeResponse.statusCode == 200 && userMeResponse.body.isNotEmpty) {
              _userDataRaw = userMeResponse.body;
              await prefs.setString('user_data_raw', userMeResponse.body);
            }
          } catch (e) {
            debugPrint("Fetch user profile error: $e");
          }

          return true;
        }
      }

      throw Exception("Giriş yapılamadı. Kullanıcı adı veya şifrenizi kontrol ediniz.");
    } catch (e) {
      debugPrint("loginAPI exception: $e");
      rethrow;
    }
  }

  Future<void> syncCookiesToWebView([String domainUrl = "https://bymfatura.com/"]) async {
    try {
      final cookieManager = CookieManager.instance();
      final url = WebUri(domainUrl);

      final cookieStr = _sessionCookie;
      if (cookieStr != null && cookieStr.isNotEmpty) {
        // Split multi-cookie Set-Cookie header string accurately
        final rawCookies = cookieStr.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'));
        for (var rawCookie in rawCookies) {
          final parts = rawCookie.split(';');
          if (parts.isNotEmpty) {
            final firstPart = parts[0].trim();
            final eqIndex = firstPart.indexOf('=');
            if (eqIndex != -1) {
              final name = firstPart.substring(0, eqIndex).trim();
              final value = firstPart.substring(eqIndex + 1).trim();
              final lowerName = name.toLowerCase();
              if (name.isNotEmpty && !['expires', 'path', 'domain', 'max-age', 'secure', 'httponly', 'samesite'].contains(lowerName)) {
                await cookieManager.setCookie(
                  url: url,
                  name: name,
                  value: value,
                  domain: "bymfatura.com",
                  path: "/",
                  isSecure: true,
                );
              }
            }
          }
        }
      }

      // Also set token cookies directly so server-side session checks pass
      final currentToken = _idToken;
      if (currentToken != null && currentToken.isNotEmpty) {
        await cookieManager.setCookie(
          url: url,
          name: "id_token",
          value: currentToken,
          domain: "bymfatura.com",
          path: "/",
          isSecure: true,
        );
        await cookieManager.setCookie(
          url: url,
          name: "token",
          value: currentToken,
          domain: "bymfatura.com",
          path: "/",
          isSecure: true,
        );
      }
    } catch (e) {
      debugPrint("syncCookiesToWebView error: $e");
    }
  }

  Future<void> init() async {
    await _loadCookie();
    await _initUserAgent();
  }

  Future<void> _initUserAgent() async {
    try {
      final defaultUa = await InAppWebViewController.getDefaultUserAgent();
      if (defaultUa.isNotEmpty) {
        // Remove WebView markers like '; wv' and 'Version/X.X' to present a pure Chrome Mobile browser UA
        _customUserAgent = defaultUa
            .replaceAll('; wv', '')
            .replaceAll(RegExp(r'Version/\d+\.\d+\s?'), '');
      }
    } catch (e) {
      debugPrint("getDefaultUserAgent error: $e");
    }
  }

  Future<void> logout() async {
    _sessionCookie = null;
    _idToken = null;
    _userDataRaw = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_cookie');
    await prefs.remove('id_token');
    await prefs.remove('user_data_raw');
    await prefs.remove('saved_dbid');
    await prefs.remove('saved_firmaid');

    final bool rememberMe = prefs.getBool('remember_me') ?? false;
    if (!rememberMe) {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.setBool('remember_me', false);
    }

    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {
      debugPrint("Logout deleteAllCookies error: $e");
    }
  }

  Future<void> _loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('auth_cookie');
    _idToken = prefs.getString('id_token');
    _userDataRaw = prefs.getString('user_data_raw');
  }

  Future<void> _saveCookie(String cookie) async {
    _sessionCookie = cookie;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_cookie', cookie);
  }

  Future<void> clearCookie() async {
    _sessionCookie = null;
    _idToken = null;
    _userDataRaw = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_cookie');
    await prefs.remove('id_token');
    await prefs.remove('user_data_raw');
  }
}
