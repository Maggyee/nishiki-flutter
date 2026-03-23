class SyncChange {
  const SyncChange({
    required this.entityType,
    required this.data,
    this.entityId,
  });

  final String entityType;
  final String? entityId;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'entityType': entityType,
    'entityId': entityId,
    'data': data,
  };
}

class SyncEnvelope {
  const SyncEnvelope({required this.latestVersion, required this.data});

  final int latestVersion;
  final Map<String, dynamic> data;
}
