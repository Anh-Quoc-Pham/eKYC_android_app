class AppConfig {
  AppConfig._();

  // Android emulator maps host machine localhost to 10.0.2.2.
  static const String apiBaseUrl = String.fromEnvironment(
    'EKYC_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
