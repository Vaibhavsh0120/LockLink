class DoorStatus {
  const DoorStatus({
    required this.online,
    required this.state,
    required this.mode,
    required this.armed,
  });
  final bool online;
  final String state;
  final String mode;
  final bool armed;

  factory DoorStatus.fromJson(Map<String, dynamic> json) {
    final online = json['online'];
    final state = json['state'];
    final mode = json['mode'] ?? 'led';
    final armed = json['armed'] ?? true;
    if (online is! bool ||
        state is! String ||
        (state != 'locked' && state != 'unlocking') ||
        (mode != 'led' && mode != 'relay') ||
        armed is! bool) {
      throw const FormatException('Unexpected device status');
    }
    return DoorStatus(online: online, state: state, mode: mode, armed: armed);
  }
}
