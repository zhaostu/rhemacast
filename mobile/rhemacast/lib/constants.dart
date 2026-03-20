class AppConfig {
  static const String serverHost = '192.168.4.1';
  static const int serverPort = 8080;
  static const String baseUrl = 'http://$serverHost:$serverPort';
  static const String wsUrl = 'ws://$serverHost:$serverPort/ws';
  static const String wsUiUrl = 'ws://$serverHost:$serverPort/ws-ui';
}
