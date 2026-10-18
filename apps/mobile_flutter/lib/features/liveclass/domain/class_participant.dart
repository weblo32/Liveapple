class ClassParticipant {
  final String identity;
  final String name;
  final String role;
  final bool isHost;
  final bool isLocal;
  final bool isMicMuted;
  final bool isCameraOff;
  final bool isSpeaking;
  final bool isHandRaised;
  final int deviceCount;
  final DateTime joinedAt;
  final bool micPubPresent;
  final bool micPubMuted;
  final bool micPubSubscribed;
  final bool camPubPresent;
  final bool camPubMuted;
  final bool camPubSubscribed;

  ClassParticipant({
    required this.identity,
    required this.name,
    this.role = 'STUDENT',
    this.isHost = false,
    this.isLocal = false,
    this.isMicMuted = true,
    this.isCameraOff = true,
    this.isSpeaking = false,
    this.isHandRaised = false,
    this.deviceCount = 1,
    DateTime? joinedAt,
    this.micPubPresent = false,
    this.micPubMuted = true,
    this.micPubSubscribed = false,
    this.camPubPresent = false,
    this.camPubMuted = true,
    this.camPubSubscribed = false,
  }) : joinedAt = joinedAt ?? DateTime.now();

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Derived real mic mute state: for remote participants, strictly derived from LiveKit publication.
  bool get isRealMicMuted {
    if (isLocal) return isMicMuted;
    if (!micPubPresent) return true;
    return micPubMuted;
  }

  /// Derived real camera off state: for remote participants, strictly derived from LiveKit publication.
  bool get isRealCameraOff {
    if (isLocal) return isCameraOff;
    if (!camPubPresent) return true;
    return camPubMuted;
  }

  ClassParticipant copyWith({
    String? identity,
    String? name,
    String? role,
    bool? isHost,
    bool? isLocal,
    bool? isMicMuted,
    bool? isCameraOff,
    bool? isSpeaking,
    bool? isHandRaised,
    int? deviceCount,
    DateTime? joinedAt,
    bool? micPubPresent,
    bool? micPubMuted,
    bool? micPubSubscribed,
    bool? camPubPresent,
    bool? camPubMuted,
    bool? camPubSubscribed,
  }) {
    return ClassParticipant(
      identity: identity ?? this.identity,
      name: name ?? this.name,
      role: role ?? this.role,
      isHost: isHost ?? this.isHost,
      isLocal: isLocal ?? this.isLocal,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      deviceCount: deviceCount ?? this.deviceCount,
      joinedAt: joinedAt ?? this.joinedAt,
      micPubPresent: micPubPresent ?? this.micPubPresent,
      micPubMuted: micPubMuted ?? this.micPubMuted,
      micPubSubscribed: micPubSubscribed ?? this.micPubSubscribed,
      camPubPresent: camPubPresent ?? this.camPubPresent,
      camPubMuted: camPubMuted ?? this.camPubMuted,
      camPubSubscribed: camPubSubscribed ?? this.camPubSubscribed,
    );
  }

  /// Single source of truth deduplication & sorting rule:
  /// 1. Deduplicates multiple devices with identical identity (userId).
  /// 2. Sorts: Host first -> Raised hands -> Alphabetical by name.
  static List<ClassParticipant> deduplicateAndSort(List<ClassParticipant> list) {
    final Map<String, ClassParticipant> map = {};

    for (final p in list) {
      if (map.containsKey(p.identity)) {
        final existing = map[p.identity]!;
        map[p.identity] = existing.copyWith(
          deviceCount: existing.deviceCount + 1,
          isHost: existing.isHost || p.isHost,
          isLocal: existing.isLocal || p.isLocal,
          isMicMuted: existing.isMicMuted && p.isMicMuted,
          isCameraOff: existing.isCameraOff && p.isCameraOff,
          isSpeaking: existing.isSpeaking || p.isSpeaking,
          isHandRaised: existing.isHandRaised || p.isHandRaised,
          micPubPresent: existing.micPubPresent || p.micPubPresent,
          micPubMuted: existing.micPubMuted && p.micPubMuted,
          micPubSubscribed: existing.micPubSubscribed || p.micPubSubscribed,
          camPubPresent: existing.camPubPresent || p.camPubPresent,
          camPubMuted: existing.camPubMuted && p.camPubMuted,
          camPubSubscribed: existing.camPubSubscribed || p.camPubSubscribed,
        );
      } else {
        map[p.identity] = p;
      }
    }

    final result = map.values.toList();
    result.sort((a, b) {
      // 1. Host first
      if (a.isHost && !b.isHost) return -1;
      if (!a.isHost && b.isHost) return 1;

      // 2. Hand raised next
      if (a.isHandRaised && !b.isHandRaised) return -1;
      if (!a.isHandRaised && b.isHandRaised) return 1;

      // 3. Alphabetical by name
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return result;
  }
}
