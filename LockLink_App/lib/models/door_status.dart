class DoorStatus {
  const DoorStatus({required this.online, required this.state});
  final bool online;
  final String state;

  factory DoorStatus.fromJson(Map<String, dynamic> json) {
    final online = json['online'];
    final state = json['state'];
    if (online is! bool ||
        state is! String ||
        (state != 'locked' && state != 'unlocking')) {
      throw const FormatException('Unexpected device status');
    }
    return DoorStatus(online: online, state: state);
  }
}
