class MatterHome {
  const MatterHome({
    required this.id,
    required this.index,
    required this.vendorId,
    required this.label,
  });

  final String id;
  final int index;
  final int vendorId;
  final String label;

  String get platform => switch (vendorId) {
    0x1349 => 'Apple Home',
    0x6006 => 'Google Home',
    _ => 'Matter home',
  };
  String get displayName => label.isEmpty ? '$platform · $index' : label;

  factory MatterHome.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(value['id'] as String) ||
        value['index'] is! int ||
        value['index'] < 1 ||
        value['index'] > 254 ||
        value['vendor_id'] is! int ||
        value['vendor_id'] < 0 ||
        value['vendor_id'] > 65535 ||
        value['label'] is! String) {
      throw const FormatException('Unexpected connected home');
    }
    return MatterHome(
      id: value['id'],
      index: value['index'],
      vendorId: value['vendor_id'],
      label: value['label'],
    );
  }
}
