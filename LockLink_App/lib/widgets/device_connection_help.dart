import 'package:flutter/material.dart';

/// Guidance stays available even when the ESP32 cannot reply.
class DeviceConnectionHelp extends StatelessWidget {
  const DeviceConnectionHelp({super.key});

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Connection help'),
    childrenPadding: const EdgeInsets.only(bottom: 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: const [
      Text(
        '1. Power on the ESP32.\n2. Connect your phone to the same Wi-Fi.\n3. Check the device address in Settings.',
      ),
      SizedBox(height: 12),
      Text(
        'Guest networks or a VPN can block local access. If the router assigns a new address, update it in Settings.',
      ),
      SizedBox(height: 12),
      Text(
        'New device without Wi-Fi? Open USB serial at 115200 baud and run PAIR for its setup code. Enter that code in your home app to pair over Bluetooth. App Terminal needs Wi-Fi.',
      ),
    ],
  );
}
