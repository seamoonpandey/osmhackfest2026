class ApiConfig {
  static const String baseUrl = 'https://api.roadmonitor.com/v1';
  // for real test make this false and the api route above this true
  static const bool useMocks = true;
  
  // Timeout settings
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration receiveTimeout = Duration(seconds: 3);
}
