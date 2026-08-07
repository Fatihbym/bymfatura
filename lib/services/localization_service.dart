import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService extends ChangeNotifier {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  String _currentLanguage = 'tr-TR';
  String get currentLanguage => _currentLanguage;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'tr-TR';
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    if (_currentLanguage == lang) return;
    _currentLanguage = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    notifyListeners();
  }

  String translate(String key) {
    return _localizedStrings[_currentLanguage]?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _localizedStrings = {
    'tr-TR': {
      'login': 'Giriş Yap',
      'email_hint': 'Kullanıcı Adı',
      'username_hint': 'Kullanıcı Adı',
      'password_hint': 'Şifre',
      'remember_me': 'Beni Hatırla',
      'forgot_password': 'Şifremi Unuttum',
      'login_desc': 'Hesabınıza giriş yaparak devam edin.',
      'error_title': 'Giriş Hatası Detayı',
      'error_msg': 'Kullanıcı Adı veya Şifre hatalıdır tekrar deneyiniz',
      'empty_error': 'Lütfen kullanıcı adı ve şifrenizi girin.',
      'login_failed': 'Giriş başarısız. Bilgilerinizi kontrol edin.',
      'ok': 'Tamam',
      
      // company_selection
      'select_company': 'Şirket ve Firma Seçimi',
      'search_company': 'Şirket veya firma adı ile arayın...',
      'no_company_found': 'Aramanızla eşleşen şirket veya firma bulunamadı.',
      'company_loading': 'Firmalar yükleniyor...',
      'click_to_see_firms': 'Firmaları görmek için dokunun',
      'firms_available': 'Firma Mevcut',
      'no_sub_firm': 'Alt firma bulunamadı.',
      'connect_to_company': 'Şirkete Bağlan',
      'continue_btn': 'Devam Et',
      'search_results': 'Arama Sonuçları',
      'companies_matched': 'Şirket Eşleşti',
      'firm_selection_fail': 'Firma seçimi başarısız oldu. Lütfen tekrar deneyin.',

      // forgot_password
      'forgot_pwd_title': 'Şifremi Unuttum',
      'forgot_pwd_desc': 'Sisteme kayıtlı VKN veya TCKN numaranızı girerek devam edin.',
      'vkn_tckn_hint': 'VKN / TCKN No',
      'forgot_pwd_btn': 'Devam Et',
      'back_to_login': 'Giriş Ekranına Dön',
      'forgot_pwd_success': 'Şifre sıfırlama işlemi tamamlandı.',
      'forgot_pwd_fail': 'İşlem başarısız oldu veya bilgiler doğrulanamadı.',
      'empty_vkn_tckn': 'Lütfen VKN veya TCKN numaranızı girin.',
      'invalid_vkn_tckn': 'VKN (10 hane) veya TCKN (11 hane) girmelisiniz.',
      'empty_email': 'Lütfen E-posta adresinizi girin.',
      'forgot_step2_title': 'Şifre Sıfırlama',
      'forgot_step2_desc': 'Lütfen Kullanıcı Adı ve E-posta adresinizi girin.',
      'username_label': 'Kullanıcı Adı',
      'email_label': 'E-posta',
      'reset_pwd_btn': 'Sıfırla',
      'empty_username': 'Lütfen Kullanıcı Adınızı girin.',
      'empty_email_val': 'Lütfen E-posta adresinizi girin.',
    },
    'en-US': {
      'login': 'Login',
      'email_hint': 'Username',
      'password_hint': 'Password',
      'remember_me': 'Remember Me',
      'forgot_password': 'Forgot Password',
      'login_desc': 'Log in to your account to continue.',
      'error_title': 'Login Error',
      'error_msg': 'Invalid username or password, please try again.',
      'empty_error': 'Please enter your username and password.',
      'login_failed': 'Login failed. Please check your credentials.',
      'ok': 'OK',
      
      // company_selection
      'select_company': 'Select Company and Firm',
      'search_company': 'Search by company or firm name...',
      'no_company_found': 'No company or firm found matching your search.',
      'company_loading': 'Loading firms...',
      'click_to_see_firms': 'Tap to see firms',
      'firms_available': 'Firms Available',
      'no_sub_firm': 'No sub-firm found.',
      'connect_to_company': 'Connect to Company',
      'continue_btn': 'Continue',
      'search_results': 'Search Results',
      'companies_matched': 'Companies Matched',
      'firm_selection_fail': 'Firm selection failed. Please try again.',

      // forgot_password
      'forgot_pwd_title': 'Forgot Password',
      'forgot_pwd_desc': 'Enter your registered VKN or TCKN number to proceed.',
      'vkn_tckn_hint': 'VKN / TCKN No',
      'forgot_pwd_btn': 'Continue',
      'back_to_login': 'Back to Login',
      'forgot_pwd_success': 'Password reset completed.',
      'forgot_pwd_fail': 'Operation failed or details could not be verified.',
      'empty_vkn_tckn': 'Please enter your VKN or TCKN number.',
      'invalid_vkn_tckn': 'Please enter a valid 10-digit VKN or 11-digit TCKN.',
      'empty_email': 'Please enter your email.',
      'forgot_step2_title': 'Reset Password',
      'forgot_step2_desc': 'Please enter your Username and Email address.',
      'username_label': 'Username',
      'email_label': 'Email',
      'reset_pwd_btn': 'Reset',
      'empty_username': 'Please enter your Username.',
      'empty_email_val': 'Please enter your Email address.',
    },
  };
}
