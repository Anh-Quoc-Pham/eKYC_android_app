enum AppEnvironment { dev, staging, prod }

class AppConfig {
  AppConfig._();

  static const String _environmentRaw = String.fromEnvironment(
    'EKYC_ENV',
    defaultValue: 'dev',
  );

  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'EKYC_API_BASE_URL',
    defaultValue: '',
  );

  // Android emulator maps host machine localhost to 10.0.2.2.
  static const String _apiBaseUrlDev = String.fromEnvironment(
    'EKYC_API_BASE_URL_DEV',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String _apiBaseUrlStaging = String.fromEnvironment(
    'EKYC_API_BASE_URL_STAGING',
    defaultValue: '',
  );

  static const String _apiBaseUrlProd = String.fromEnvironment(
    'EKYC_API_BASE_URL_PROD',
    defaultValue: '',
  );

  static const String _deviceTrustModeRaw = String.fromEnvironment(
    'EKYC_DEVICE_TRUST_MODE',
    defaultValue: 'mock_unavailable',
  );

  static const String _playIntegrityEnabledRaw = String.fromEnvironment(
    'EKYC_PLAY_INTEGRITY_ENABLED',
    defaultValue: 'true',
  );

  static const String _playIntegrityCloudProjectNumberRaw =
      String.fromEnvironment(
        'EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
        defaultValue: '',
      );

  static const String _apiClientApiKeyRaw = String.fromEnvironment(
    'EKYC_API_KEY',
    defaultValue: '',
  );

  static const String _apiClientBearerTokenRaw = String.fromEnvironment(
    'EKYC_API_BEARER_TOKEN',
    defaultValue: '',
  );

  static AppEnvironment get environment {
    switch (_environmentRaw.toLowerCase()) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }

  static String get apiBaseUrl {
    final overrideValue = _apiBaseUrlOverride.trim();
    if (overrideValue.isNotEmpty) {
      return _normalizeAndValidate(
        overrideValue,
        source: 'EKYC_API_BASE_URL',
        env: environment,
      );
    }

    switch (environment) {
      case AppEnvironment.dev:
        return _normalizeAndValidate(
          _apiBaseUrlDev,
          source: 'EKYC_API_BASE_URL_DEV',
          env: AppEnvironment.dev,
        );
      case AppEnvironment.staging:
        return _normalizeAndValidate(
          _apiBaseUrlStaging,
          source: 'EKYC_API_BASE_URL_STAGING',
          env: AppEnvironment.staging,
        );
      case AppEnvironment.prod:
        return _normalizeAndValidate(
          _apiBaseUrlProd,
          source: 'EKYC_API_BASE_URL_PROD',
          env: AppEnvironment.prod,
        );
    }
  }

  static String get deviceTrustMode => _deviceTrustModeRaw.trim().toLowerCase();

  static bool get isProductionLike => environment != AppEnvironment.dev;

  static bool get playIntegrityEnabled =>
      _parseBool(_playIntegrityEnabledRaw, defaultValue: true);

  static int? get playIntegrityCloudProjectNumber {
    final raw = _playIntegrityCloudProjectNumberRaw.trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed;
  }

  static String get playIntegrityChannel => 'ekyc/play_integrity';

  static bool get shouldUseRealPlayIntegrity =>
      isProductionLike && playIntegrityEnabled;

  static String? get apiClientApiKey {
    final value = _apiClientApiKeyRaw.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  static String? get apiClientBearerToken {
    final value = _apiClientBearerTokenRaw.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  static bool get hasApiClientCredentials =>
      apiClientApiKey != null || apiClientBearerToken != null;

  static String _normalizeAndValidate(
    String rawValue, {
    required String source,
    required AppEnvironment env,
  }) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      throw StateError('Thiếu cấu hình $source cho môi trường ${env.name}.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Giá trị $source không phải URL hợp lệ: $value');
    }

    if (env != AppEnvironment.dev && uri.scheme.toLowerCase() != 'https') {
      throw StateError('Môi trường ${env.name} bắt buộc dùng HTTPS: $value');
    }

    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static bool _parseBool(String raw, {required bool defaultValue}) {
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return defaultValue;
    }
  }
}
