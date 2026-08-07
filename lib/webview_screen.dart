import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:collection';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// Projenizdeki mevcut servisler
import 'services/deep_link_service.dart';
import 'services/auth_service.dart';

class WebViewScreen extends StatefulWidget {
  final DeepLinkService deepLinkService;
  final String? initialUrl;

  const WebViewScreen({
    super.key,
    required this.deepLinkService,
    this.initialUrl,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  
  bool _isReloading = false;
  bool _isFirstLoad = true;
  bool _hasInternet = true;
  bool _hasTimeoutError = false; 
  bool _isLoggingOut = false;

  Timer? _loadingTimeoutTimer;

  // File Download UI States
  bool _isDownloading = false;
  String _downloadingFileName = '';
  double _downloadProgress = 0.0;
  DateTime? currentBackPressTime;
  
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  late final StreamSubscription<Uri> _deepLinkSubscription;
  late PullToRefreshController pullToRefreshController;

  void _syncCookies() async {
    final cookieStr = AuthService().sessionCookie;
    if (cookieStr != null && cookieStr.isNotEmpty) {
      final cookieManager = CookieManager.instance();
      final url = WebUri(widget.initialUrl ?? "https://bymfatura.com/accounting/");
      final parts = cookieStr.split(';');
      
      for (var part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final eqIndex = trimmed.indexOf('=');
        if (eqIndex != -1) {
          final name = trimmed.substring(0, eqIndex).trim();
          final value = trimmed.substring(eqIndex + 1).trim();
          if (name.isNotEmpty && !['expires', 'path', 'domain', 'max-age', 'secure', 'httponly', 'samesite'].contains(name.toLowerCase())) {
            await cookieManager.setCookie(
              url: url,
              name: name,
              value: value,
              isSecure: true,
            );
          }
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      FlutterNativeSplash.remove();
    } catch (_) {}

    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    _syncCookies();

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.black87,
        backgroundColor: Colors.white,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          try {
            _webViewController?.reload();
          } catch (_) {}
        } else if (Platform.isIOS) {
          try {
            _webViewController?.loadUrl(urlRequest: URLRequest(url: await _webViewController?.getUrl()));
          } catch (_) {}
        }
      },
    );
    
    _deepLinkSubscription = widget.deepLinkService.uriStream.listen((Uri uri) {
      if (_webViewController != null && !_isLoggingOut) {
        try {
          _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
        } catch (_) {}
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final hasInternet = !results.contains(ConnectivityResult.none);
      if (mounted && _hasInternet != hasInternet) {
        setState(() {
          _hasInternet = hasInternet;
        });
        if (hasInternet && !_isFirstLoad && !_isLoggingOut) {
          _reloadPage();
        }
      }
    });

    Connectivity().checkConnectivity().then((results) {
      final hasInternet = !results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _hasInternet = hasInternet);
    });
  }

  @override
  void dispose() {
    _loadingTimeoutTimer?.cancel();
    _connectivitySubscription.cancel();
    _deepLinkSubscription.cancel();
    super.dispose();
  }

  void _reloadPage() {
    if (!mounted) return;
    setState(() {
      _isReloading = true;
      _hasTimeoutError = false; 
    });
    
    try {
      if (_webViewController != null) {
        _webViewController!.reload();
      }
    } catch (e) {
      debugPrint("WebView Reload Exception: $e");
    }
  }

  void _showDownloadSnackBar(String message, {bool isSuccess = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Nunito Sans', fontWeight: FontWeight.w600),
        ),
        backgroundColor: isSuccess ? const Color(0xFF0075FF) : Colors.redAccent.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _extractDynamicFilename(String? contentDisposition, String? suggestedFilename, String urlStr) {
    if (contentDisposition != null && contentDisposition.isNotEmpty) {
      final cd = contentDisposition;
      final utf8Match = RegExp(r"filename\*=UTF-8''([^;\s]+)", caseSensitive: false).firstMatch(cd);
      if (utf8Match != null && utf8Match.group(1) != null) {
        final decoded = Uri.decodeComponent(utf8Match.group(1)!);
        if (decoded.trim().isNotEmpty) return _sanitizeFilename(decoded);
      }

      final normalMatch = RegExp(r'filename="?([^";\s]+)"?', caseSensitive: false).firstMatch(cd);
      if (normalMatch != null && normalMatch.group(1) != null) {
        final name = normalMatch.group(1)!;
        if (name.trim().isNotEmpty) return _sanitizeFilename(name);
      }
    }

    if (suggestedFilename != null && suggestedFilename.trim().isNotEmpty) {
      return _sanitizeFilename(suggestedFilename);
    }

    try {
      final uri = Uri.parse(urlStr);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final lastSegment = Uri.decodeComponent(segments.last).trim();
        if (lastSegment.isNotEmpty && lastSegment.contains('.')) {
          return _sanitizeFilename(lastSegment);
        }
      }
    } catch (_) {}

    return 'dosya_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  String _getExtensionFromMime(String? mimeType) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.contains('pdf')) return '.pdf';
    if (mime.contains('wordprocessingml') || mime.contains('msword') || mime.contains('word')) return '.docx';
    if (mime.contains('spreadsheetml') || mime.contains('excel') || mime.contains('spreadsheet')) return '.xlsx';
    if (mime.contains('presentationml') || mime.contains('powerpoint')) return '.pptx';
    if (mime.contains('xml')) return '.xml';
    if (mime.contains('text/plain') || mime.contains('txt')) return '.txt';
    if (mime.contains('zip')) return '.zip';
    if (mime.contains('rar')) return '.rar';
    if (mime.contains('7z')) return '.7z';
    if (mime.contains('json')) return '.json';
    if (mime.contains('csv')) return '.csv';
    if (mime.contains('png')) return '.png';
    if (mime.contains('jpg') || mime.contains('jpeg')) return '.jpg';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('svg')) return '.svg';
    if (mime.contains('audio') || mime.contains('mp3') || mime.contains('wav')) return '.mp3';
    if (mime.contains('video') || mime.contains('mp4')) return '.mp4';
    return '.bin';
  }

  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        if (await Permission.storage.isGranted) return true;
        final status = await Permission.storage.request();
        if (status.isGranted) return true;

        if (await Permission.photos.isGranted) return true;
        final photoStatus = await Permission.photos.request();
        return photoStatus.isGranted || status.isGranted || status.isLimited;
      } else if (Platform.isIOS) {
        if (await Permission.photos.isGranted) return true;
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      }
    } catch (e) {
      debugPrint("Permission request error: $e");
    }
    return true;
  }

  void _startDownloadUI(String filename) {
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadingFileName = filename;
        _downloadProgress = 0.2;
      });
    }
  }

  void _updateDownloadProgress(double progress) {
    if (mounted) {
      setState(() {
        _downloadProgress = progress;
      });
    }
  }

  void _finishDownloadUI() {
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });
    }
  }

  Future<void> _saveToPublicDownloads(File sourceFile, String filename) async {
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        targetDir = Directory('/storage/emulated/0/Download');
        if (!targetDir.existsSync()) {
          targetDir = await getExternalStorageDirectory();
        }
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }

      if (targetDir != null) {
        final File destination = File('${targetDir.path}/$filename');
        await sourceFile.copy(destination.path);
        _showDownloadSnackBar('📥 İndirilenler klasörüne kaydedildi: $filename', isSuccess: true);
      }
    } catch (e) {
      debugPrint("Save to public downloads error: $e");
      _showDownloadSnackBar('İndirilenler klasörüne kaydedilirken hata oluştu.', isSuccess: false);
    }
  }

  String _shortenFileName(String name, {int maxLength = 32}) {
    final trimmed = name.trim();
    if (trimmed.length <= maxLength) return trimmed;

    final extIndex = trimmed.lastIndexOf('.');
    String baseName = trimmed;
    String ext = '';
    if (extIndex != -1 && extIndex > trimmed.length - 8) {
      baseName = trimmed.substring(0, extIndex);
      ext = trimmed.substring(extIndex);
    }

    if (baseName.length > 20) {
      final start = baseName.substring(0, 14);
      final end = baseName.substring(baseName.length - 7);
      return '$start...$end$ext';
    }
    return trimmed;
  }

  void _showFileDownloadedBottomSheet({
    required File savedFile,
    required String filename,
  }) {
    if (!mounted) return;

    final String displayName = _shortenFileName(filename);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 20,
                spreadRadius: 1,
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontFamily: 'Nunito Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Dosya başarıyla indirildi',
                    style: TextStyle(
                      fontFamily: 'Nunito Sans',
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_copy_rounded, color: Color(0xFF16A34A), size: 20),
                ),
                title: const Text(
                  "İndirilenler'e Kaydet",
                  style: TextStyle(
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
                subtitle: const Text(
                  'Cihazın İndirilenler klasörüne kaydeder',
                  style: TextStyle(fontFamily: 'Nunito Sans', fontSize: 12, color: Color(0xFF64748B)),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _saveToPublicDownloads(savedFile, filename);
                },
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.drive_file_move_rounded, color: Color(0xFF0075FF), size: 20),
                ),
                title: const Text(
                  'Farklı Kaydet / Paylaş',
                  style: TextStyle(
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
                subtitle: const Text(
                  'Dosyalar, Drive veya başka uygulamada saklayın',
                  style: TextStyle(fontFamily: 'Nunito Sans', fontSize: 12, color: Color(0xFF64748B)),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await SharePlus.instance.share(ShareParams(files: [XFile(savedFile.path)]));
                },
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.open_in_new_rounded, color: Color(0xFFD97706), size: 20),
                ),
                title: const Text(
                  'Dosyayı Aç',
                  style: TextStyle(
                    fontFamily: 'Nunito Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1E293B),
                  ),
                ),
                subtitle: const Text(
                  'Varsayılan uygulama ile açar',
                  style: TextStyle(fontFamily: 'Nunito Sans', fontSize: 12, color: Color(0xFF64748B)),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final Uri fileUri = Uri.file(savedFile.path);
                    if (await canLaunchUrl(fileUri)) {
                      await launchUrl(fileUri);
                    }
                  } catch (e) {
                    _showDownloadSnackBar('Dosya açılamadı: $filename', isSuccess: false);
                  }
                },
              ),

              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAndOpenFileFromBytes({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    try {
      await _requestStoragePermission();

      String finalFilename = filename.trim();
      if (finalFilename.isEmpty) {
        finalFilename = 'dosya_${DateTime.now().millisecondsSinceEpoch}';
      }

      if (!finalFilename.contains('.')) {
        final ext = _getExtensionFromMime(mimeType);
        finalFilename = '$finalFilename$ext';
      }

      _startDownloadUI(finalFilename);
      await Future.delayed(const Duration(milliseconds: 300));
      _updateDownloadProgress(0.6);

      final Directory appDir = Platform.isAndroid
          ? (await getExternalStorageDirectory()) ?? (await getApplicationDocumentsDirectory())
          : await getApplicationDocumentsDirectory();

      final File file = File('${appDir.path}/$finalFilename');
      await file.writeAsBytes(bytes);
      _updateDownloadProgress(1.0);
      await Future.delayed(const Duration(milliseconds: 300));
      _finishDownloadUI();

      // Automatically save copy to public Downloads folder by default as well
      await _saveToPublicDownloads(file, finalFilename);

      // Open interactive Save & Location Bottom Sheet
      _showFileDownloadedBottomSheet(
        savedFile: file,
        filename: finalFilename,
      );
    } catch (e) {
      _finishDownloadUI();
      debugPrint("Save File Error: $e");
      _showDownloadSnackBar('Dosya kaydedilirken hata oluştu: $filename', isSuccess: false);
    }
  }

  bool _isLoginOrLogoutUrl(WebUri? url) {
    if (url == null) return false;
    final path = url.path.toLowerCase();
    final full = url.toString().toLowerCase();
    return path.contains('/auth/login') || 
           path.endsWith('/login') || 
           path.contains('/auth/logout') || 
           path.endsWith('/logout') ||
           full.contains('/auth/login') ||
           full.contains('/auth/logout') ||
           full.contains('/accounting/login');
  }

  void _startLoadingTimeoutTimer() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 15), () async {
      if (mounted && (_isFirstLoad || _isReloading)) {
        final currentUrl = await _webViewController?.getUrl();
        if (_isLoginOrLogoutUrl(currentUrl)) {
          debugPrint("Login timeout on login page. Navigating back to LoginScreen.");
          _showDownloadSnackBar('Giriş zaman aşımına uğradı veya kullanıcı bilgileri hatalı.', isSuccess: false);
          _handleLogout();
        } else {
          setState(() {
            _isFirstLoad = false;
            _isReloading = false;
          });
        }
      }
    });
  }

  void _cancelLoadingTimeoutTimer() {
    _loadingTimeoutTimer?.cancel();
  }



  void _triggerNativeLogout() {
    if (_isLoggingOut) return;
    if (mounted) {
      setState(() {
        _isLoggingOut = true;
      });
    }
    _handleLogout();
  }

  void _handleLogout() async {
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (_) {}
    await AuthService().logout();
    if (mounted) {
      setState(() {
        _isLoggingOut = false;
        _isFirstLoad = true;
      });
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri("https://bymfatura.com/accounting/login")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggingOut) {
      return const Scaffold(
        backgroundColor: Color(0xFFFCFCFC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0075ff)),
        ),
      );
    }

    final messenger = ScaffoldMessenger.of(context);
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_webViewController != null) {
          try {
            if (await _webViewController!.canGoBack()) {
              _webViewController!.goBack();
              return;
            }
          } catch (_) {}
        }

        DateTime now = DateTime.now();
        if (currentBackPressTime == null || now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
          currentBackPressTime = now;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Çıkmak için tekrar basın'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          // KESİN ÇÖZÜM: InAppWebView HER ZAMAN ağaçta kalır.
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.initialUrl ?? "https://bymfatura.com/accounting/"),
                  headers: {
                    if (AuthService().sessionCookie != null && AuthService().sessionCookie!.isNotEmpty)
                      'Cookie': AuthService().sessionCookie!,
                  },
                ),
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: """
                      (function() {
                        var token = '${AuthService().idToken ?? ""}';
                        var userData = ${AuthService().userDataRaw != null && AuthService().userDataRaw!.isNotEmpty ? AuthService().userDataRaw : "null"};
                        if (token && token.length > 0) {
                          try {
                            localStorage.setItem('id_token', token);
                            localStorage.setItem('token', token);
                            sessionStorage.setItem('id_token', token);
                          } catch(e) {}
                        }
                        if (userData) {
                          try {
                            localStorage.setItem('user', typeof userData === 'string' ? userData : JSON.stringify(userData));
                          } catch(e) {}
                        }
                      })();
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  )
                ]),
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  userAgent: AuthService().customUserAgent, // Custom User-Agent to hide 'wv' WebView flags
                  useHybridComposition: false, // Performance improvement
                  allowsBackForwardNavigationGestures: true,
                  thirdPartyCookiesEnabled: true,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  supportMultipleWindows: false,
                ),
                onDownloadStartRequest: (controller, downloadStartRequest) async {
                  debugPrint("File Download Requested: ${downloadStartRequest.url}");
                  final urlStr = downloadStartRequest.url.toString();

                  if (urlStr.startsWith('data:')) {
                    final parts = urlStr.split(',');
                    if (parts.length > 1) {
                      final meta = parts[0];
                      final base64Str = parts[1];
                      final mime = meta.split(';')[0].replaceFirst('data:', '');
                      final dynamicName = _extractDynamicFilename(null, downloadStartRequest.suggestedFilename, urlStr);
                      await _saveAndOpenFileFromBytes(
                        bytes: base64Decode(base64Str),
                        filename: dynamicName,
                        mimeType: mime,
                      );
                      return;
                    }
                  }

                  if (urlStr.startsWith('http://') || urlStr.startsWith('https://')) {
                    String dynamicName = downloadStartRequest.suggestedFilename ?? '';
                    try {
                      final headers = <String, String>{};
                      if (AuthService().sessionCookie != null && AuthService().sessionCookie!.isNotEmpty) {
                        headers['Cookie'] = AuthService().sessionCookie!;
                      }

                      final response = await http.get(Uri.parse(urlStr), headers: headers);
                      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
                        final contentDisposition = response.headers['content-disposition'];
                        final mimeType = response.headers['content-type'] ?? '';
                        dynamicName = _extractDynamicFilename(contentDisposition, downloadStartRequest.suggestedFilename, urlStr);
                        
                        await _saveAndOpenFileFromBytes(
                          bytes: response.bodyBytes,
                          filename: dynamicName,
                          mimeType: mimeType,
                        );
                        return;
                      }
                    } catch (e) {
                      debugPrint("Direct HTTP Download Error: $e");
                    }

                    dynamicName = _extractDynamicFilename(null, downloadStartRequest.suggestedFilename, urlStr);
                    final Uri downloadUri = Uri.parse(urlStr);
                    if (await canLaunchUrl(downloadUri)) {
                      await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
                      _showDownloadSnackBar('İndirme başlatıldı: $dynamicName', isSuccess: true);
                    } else {
                      _showDownloadSnackBar('Dosya indirilemedi: $dynamicName', isSuccess: false);
                    }
                  }
                },
                onCreateWindow: (controller, createWindowAction) async {
                  final url = createWindowAction.request.url;
                  if (url != null) {
                    _webViewController?.loadUrl(urlRequest: URLRequest(url: url));
                    return true;
                  }
                  return false;
                },
                onConsoleMessage: (controller, consoleMessage) {
                  if (kDebugMode && consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
                    debugPrint("Web Error: ${consoleMessage.message}");
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final url = navigationAction.request.url;
                  if (url != null) {
                    final scheme = url.scheme.toLowerCase();
                    final host = url.host.toLowerCase();

                    // 1. External Schemes (tel:, mailto:, whatsapp:, etc.)
                    if (!['http', 'https', 'file', 'chrome', 'data', 'javascript', 'about'].contains(scheme)) {
                      final uri = Uri.parse(url.toString());
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    // 2. Strict Domain Lock Constraint: Prevent leaving bymfatura.com inside WebView
                    if (scheme == 'http' || scheme == 'https') {
                      final isBymDomain = host.endsWith('bymfatura.com') || host == 'bymfatura.com';
                      if (!isBymDomain) {
                        debugPrint("External domain navigation blocked inside WebView: $url");
                        final uri = Uri.parse(url.toString());
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                    }

                    final path = url.path.toLowerCase();
                    final full = url.toString().toLowerCase();
                    final isLogout = path.contains('/auth/logout') || path.endsWith('/logout') || full.contains('/auth/logout');
                    if (isLogout) {
                      _triggerNativeLogout();
                      return NavigationActionPolicy.CANCEL;
                    }
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                pullToRefreshController: pullToRefreshController,
                
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  try {
                    controller.addJavaScriptHandler(
                      handlerName: 'downloadBase64File',
                      callback: (args) async {
                        if (args.isEmpty) return;
                        try {
                          final data = args[0] as Map<String, dynamic>;
                          final String filename = data['filename'] ?? 'dosya';
                          final String base64Data = data['base64Data'] ?? '';
                          final String mimeType = data['mimeType'] ?? '';

                          if (base64Data.isNotEmpty) {
                            final bytes = base64Decode(base64Data);
                            await _saveAndOpenFileFromBytes(
                              bytes: bytes,
                              filename: filename,
                              mimeType: mimeType,
                            );
                          }
                        } catch (e) {
                          debugPrint("downloadBase64File Handler Exception: $e");
                        }
                      },
                    );
                    controller.addJavaScriptHandler(
                      handlerName: 'onExplicitLogoutClicked',
                      callback: (args) {
                        _triggerNativeLogout();
                      },
                    );
                  } catch (e) {
                    debugPrint("JS Handler Exception: $e");
                  }
                },
                
                onLoadStart: (controller, url) {
                  if (mounted && _hasTimeoutError) {
                    setState(() => _hasTimeoutError = false);
                  }
                  _startLoadingTimeoutTimer(); 
                },
                
                onUpdateVisitedHistory: (controller, url, isReload) {
                  if (url != null && !_isLoginOrLogoutUrl(url)) {
                    if (mounted && (_isFirstLoad || _isReloading)) {
                      _cancelLoadingTimeoutTimer();
                      setState(() {
                        _isFirstLoad = false;
                        _isReloading = false;
                      });
                    }
                  } else if (url != null && _isLoginOrLogoutUrl(url)) {
                    if (mounted && !_isFirstLoad) {
                      setState(() {
                        _isFirstLoad = true;
                      });
                    }
                  }
                },
                
                onProgressChanged: (controller, progress) async {
                  if (progress == 100 && mounted) {
                    try {
                      final currentUrl = await controller.getUrl();
                      final isLogin = _isLoginOrLogoutUrl(currentUrl);
                      
                      if (!isLogin) {
                        _cancelLoadingTimeoutTimer();
                        if (_isFirstLoad || _isReloading) {
                          setState(() {
                            _isFirstLoad = false;
                            _isReloading = false;
                            _hasTimeoutError = false;
                          });
                        }
                      }
                    } catch (_) {}
                  }
                },
                
                onLoadStop: (controller, url) async {
                  pullToRefreshController.endRefreshing();
                  _cancelLoadingTimeoutTimer();

                  try {
                    await controller.evaluateJavascript(source: """
                      if (!window._downloadInterceptorAdded) {
                        window._downloadInterceptorAdded = true;
                        document.addEventListener('click', function(e) {
                          var anchor = e.target ? e.target.closest('a') : null;
                          if (anchor && anchor.href) {
                            var href = anchor.href;
                            var downloadAttr = anchor.getAttribute('download');
                            
                            if (downloadAttr !== null || href.indexOf('blob:') === 0 || href.indexOf('data:') === 0) {
                              e.preventDefault();
                              e.stopPropagation();

                              if (href.indexOf('data:') === 0) {
                                var parts = href.split(',');
                                var meta = parts[0];
                                var base64Data = parts[1];
                                var mimeType = meta.split(';')[0].replace('data:', '');
                                var filename = downloadAttr || ('dosya_' + Date.now());
                                
                                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                  window.flutter_inappwebview.callHandler('downloadBase64File', {
                                    filename: filename,
                                    mimeType: mimeType,
                                    base64Data: base64Data
                                  });
                                }
                              } else if (href.indexOf('blob:') === 0) {
                                var xhr = new XMLHttpRequest();
                                xhr.open('GET', href, true);
                                xhr.responseType = 'blob';
                                xhr.onload = function() {
                                  if (xhr.status === 200 || xhr.status === 0) {
                                    var blob = xhr.response;
                                    var reader = new FileReader();
                                    reader.onloadend = function() {
                                      var result = reader.result || '';
                                      var base64Data = result.split(',')[1] || '';
                                      var filename = downloadAttr || ('dosya_' + Date.now());
                                      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                        window.flutter_inappwebview.callHandler('downloadBase64File', {
                                          filename: filename,
                                          mimeType: blob.type,
                                          base64Data: base64Data
                                        });
                                      }
                                    };
                                    reader.readAsDataURL(blob);
                                  }
                                };
                                xhr.send();
                              }
                            }
                          }
                        }, true);
                      }
                    """);
                  } catch (_) {}

                  // Sadece web tarafının kendi siyah loader'ını gizler
                  try {
                    await controller.evaluateJavascript(source: """
                      if (!window._pageLoaderStyleAdded) {
                        var targetHead = document.head || document.documentElement;
                        if (targetHead) {
                          window._pageLoaderStyleAdded = true;
                          var style = document.createElement('style');
                          style.innerHTML = '.app-page-loader { display: none !important; visibility: hidden !important; opacity: 0 !important; pointer-events: none !important; }';
                          targetHead.appendChild(style);
                        }
                      }
                    """);
                  } catch (_) {}

                  try {
                    await controller.evaluateJavascript(source: """
                      if (!window._reconnectCardObserverAdded) {
                        var targetBody = document.body || document.documentElement;
                        if (targetBody) {
                          window._reconnectCardObserverAdded = true;
                          function checkReconnectCard() {
                            var card = document.querySelector('.bym-reconnect-card');
                            if (card) {
                              card.style.display = 'none';
                              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                window.flutter_inappwebview.callHandler('onSessionExpiredCardDetected');
                              }
                            }
                          }
                          var observer = new MutationObserver(checkReconnectCard);
                          observer.observe(targetBody, { childList: true, subtree: true });
                          checkReconnectCard();
                        }
                      }
                    """);
                  } catch (_) {}

                  try {
                    await controller.evaluateJavascript(source: """
                      if (!window._logoutListenerAdded) {
                        window._logoutListenerAdded = true;
                        document.addEventListener('click', function(e) {
                          var target = e.target ? e.target.closest('button, a, div, span, li') : null;
                          if (target) {
                            var text = (target.innerText || target.textContent || '').trim();
                            var lowerText = text.toLowerCase();
                            var isDangerClass = target.classList && target.classList.contains('danger');
                            var isInsideProfile = !!target.closest('#profileButton, .user-profile, .profile-dropdown, .dropdown-menu');

                            var isExactLogoutText = (
                              lowerText === 'çıkış' ||
                              lowerText === 'çıkış yap' ||
                              lowerText === 'oturum kapat' ||
                              lowerText === 'oturumu kapat' ||
                              lowerText === 'logout' ||
                              lowerText === 'log out' ||
                              lowerText === 'sign out'
                            );

                            var isPartialLogoutText = (
                              lowerText.indexOf('oturumu kapat') !== -1 ||
                              lowerText.indexOf('oturum kapat') !== -1 ||
                              lowerText.indexOf('çıkış yap') !== -1 ||
                              (isInsideProfile && lowerText.indexOf('çıkış') !== -1) ||
                              (isDangerClass && lowerText.indexOf('oturum') !== -1)
                            );

                            if (isExactLogoutText || isPartialLogoutText) {
                              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                window.flutter_inappwebview.callHandler('onExplicitLogoutClicked');
                              }
                            }
                          }
                        }, true);
                      }
                    """);
                  } catch (_) {}

                  pullToRefreshController.endRefreshing();
                  _cancelLoadingTimeoutTimer();
                  if (mounted && (_isFirstLoad || _isReloading)) {
                    setState(() {
                      _isFirstLoad = false;
                      _isReloading = false;
                    });
                  }
                },
                onReceivedError: (controller, request, error) {
                  pullToRefreshController.endRefreshing();
                  if (request.isForMainFrame == true) {
                    debugPrint("CRITICAL WEB ERROR: ${error.description}");
                    if (mounted) {
                      setState(() {
                        _isFirstLoad = false;
                        _isReloading = false;
                        _hasTimeoutError = true;
                      });
                    }
                  }
                },
              ),
              
              if (_isFirstLoad || _isReloading || _isLoggingOut)
                Container(
                  color: const Color(0xFFF8FAFC),
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Hero(
                          tag: 'app_logo',
                          child: Image.asset(
                            'assets/logo.png',
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/app_icon.png',
                                height: 220,
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 36),
                        const CircularProgressIndicator(
                          color: Color(0xFF0075FF),
                          strokeWidth: 3.5,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Giriş Yapılıyor...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Nunito Sans',
                            color: Color(0xFF64748B),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),




              if (!_hasInternet || _hasTimeoutError)
                Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            !_hasInternet ? Icons.wifi_off_rounded : Icons.timer_off_rounded, 
                            size: 72, 
                            color: Colors.grey.shade400
                          ),
                          const SizedBox(height: 16),
                          Text(
                            !_hasInternet ? 'İnternet Bağlantısı Yok' : 'Bağlantı Zaman Aşımı',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            !_hasInternet 
                                ? 'Lütfen internet bağlantınızı kontrol edip tekrar deneyin.'
                                : 'Sunucu yanıt vermedi veya sayfa yüklemesi çok uzun sürdü. Lütfen oturumunuzu tazeleyin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, height: 1.4, fontSize: 15),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _triggerNativeLogout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0075FF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.login_rounded, size: 22),
                              label: const Text('Yeniden Giriş Yap', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Floating Download Progress Bar at Bottom of Screen
              if (_isDownloading)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF0F172A),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF0075FF),
                                  strokeWidth: 2.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Dosya İndiriliyor: $_downloadingFileName',
                                  style: const TextStyle(
                                    fontFamily: 'Nunito Sans',
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _downloadProgress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0075FF)),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}