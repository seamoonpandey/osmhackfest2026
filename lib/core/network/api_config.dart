class ApiConfig {
  static const String baseUrl = 'http://172.0.22.80:8000/';
  // for real test make this false and the api route above this true
  static const bool useMocks = false;

  // Timeout settings
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
