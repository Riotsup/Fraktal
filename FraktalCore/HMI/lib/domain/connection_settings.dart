library;

/// Transport selected by the connection wizard. The gateway option is the
/// deployment seam for OPC UA/ADS on native platforms and WebSocket/REST on Web.
enum ConnectionTransport { gateway, simulation }

class ConnectionSettings {
  final ConnectionTransport transport;
  final String endpoint;
  final bool everConnected;

  /// Stable root-Unit browse paths this HMI is allowed to display and command.
  /// An empty list is valid only while the second wizard step is incomplete.
  final List<String> selectedUnitPaths;
  final bool unitSelectionComplete;
  final List<String> enabledLanguageCodes;
  final String activeLanguageCode;
  final bool languageSelectionComplete;

  const ConnectionSettings({
    this.transport = ConnectionTransport.gateway,
    this.endpoint = 'ws://127.0.0.1:8080/fraktal',
    this.everConnected = false,
    this.selectedUnitPaths = const [],
    this.unitSelectionComplete = false,
    this.enabledLanguageCodes = const [],
    this.activeLanguageCode = 'en',
    this.languageSelectionComplete = false,
  });

  ConnectionSettings copyWith({
    ConnectionTransport? transport,
    String? endpoint,
    bool? everConnected,
    List<String>? selectedUnitPaths,
    bool? unitSelectionComplete,
    List<String>? enabledLanguageCodes,
    String? activeLanguageCode,
    bool? languageSelectionComplete,
  }) =>
      ConnectionSettings(
        transport: transport ?? this.transport,
        endpoint: endpoint ?? this.endpoint,
        everConnected: everConnected ?? this.everConnected,
        selectedUnitPaths: selectedUnitPaths ?? this.selectedUnitPaths,
        unitSelectionComplete:
            unitSelectionComplete ?? this.unitSelectionComplete,
        enabledLanguageCodes: enabledLanguageCodes ?? this.enabledLanguageCodes,
        activeLanguageCode: activeLanguageCode ?? this.activeLanguageCode,
        languageSelectionComplete:
            languageSelectionComplete ?? this.languageSelectionComplete,
      );

  Map<String, Object> toJson() => {
        'schemaVersion': 3,
        'transport': transport.name,
        'endpoint': endpoint,
        'everConnected': everConnected,
        'selectedUnitPaths': selectedUnitPaths,
        'unitSelectionComplete': unitSelectionComplete,
        'enabledLanguageCodes': enabledLanguageCodes,
        'activeLanguageCode': activeLanguageCode,
        'languageSelectionComplete': languageSelectionComplete,
      };

  static ConnectionSettings? fromJson(Object? value) {
    if (value is! Map) return null;
    final schemaVersion = value['schemaVersion'];
    if (schemaVersion != 1 && schemaVersion != 2 && schemaVersion != 3) {
      return null;
    }
    final transportName = value['transport'];
    final endpoint = value['endpoint'];
    final everConnected = value['everConnected'];
    if (transportName is! String ||
        endpoint is! String ||
        everConnected is! bool) return null;
    ConnectionTransport? transport;
    for (final candidate in ConnectionTransport.values) {
      if (candidate.name == transportName) transport = candidate;
    }
    if (transport == null) return null;
    final selected = schemaVersion >= 2 ? value['selectedUnitPaths'] : null;
    final selectionComplete =
        schemaVersion >= 2 ? value['unitSelectionComplete'] : null;
    if (schemaVersion >= 2 &&
        (selected is! List ||
            selected.any((item) => item is! String) ||
            selectionComplete is! bool)) {
      return null;
    }
    final languages = schemaVersion == 3 ? value['enabledLanguageCodes'] : null;
    final activeLanguage =
        schemaVersion == 3 ? value['activeLanguageCode'] : null;
    final languageComplete =
        schemaVersion == 3 ? value['languageSelectionComplete'] : null;
    if (schemaVersion == 3 &&
        (languages is! List ||
            languages.any((item) => item is! String) ||
            activeLanguage is! String ||
            languageComplete is! bool)) {
      return null;
    }
    return ConnectionSettings(
      transport: transport,
      endpoint: endpoint,
      everConnected: everConnected,
      selectedUnitPaths:
          selected == null ? const [] : List<String>.from(selected),
      unitSelectionComplete: selectionComplete == true,
      enabledLanguageCodes:
          languages == null ? const [] : List<String>.from(languages),
      activeLanguageCode: activeLanguage is String ? activeLanguage : 'en',
      languageSelectionComplete: languageComplete == true,
    );
  }
}
