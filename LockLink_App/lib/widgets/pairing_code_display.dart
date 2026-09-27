import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/terminal_session.dart';

Future<void> showPairingQr(BuildContext context, TerminalSession session) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PairingQrDialog(session: session),
    );

/// The same local-only pairing view is used in guides and the terminal dialog.
class PairingCodeDisplay extends StatelessWidget {
  const PairingCodeDisplay({
    super.key,
    required this.session,
    this.enlarged = false,
  });
  final TerminalSession session;
  final bool enlarged;

  Future<void> _copy(BuildContext context) async {
    final code = session.pairingCode;
    if (code == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Setup code copied.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not copy. Select the code to copy manually.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final code = session.pairingCode;
      if (code == null) return const SizedBox.shrink();
      final payload = session.pairingQrPayload;
      final qr = payload == null
          ? null
          : QrValidator.validate(
              data: payload,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ).qrCode;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Matter setup code'),
          const SizedBox(height: 12),
          if (qr != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final maxSide = math.min(
                  enlarged ? 420.0 : 260.0,
                  constraints.maxWidth,
                );
                // qr_flutter rounds its module pitch to half a logical pixel.
                // Match that pitch so its painter cannot eat into the border.
                final moduleSize =
                    (maxSide / (qr.moduleCount + 8) * 2).floorToDouble() / 2;
                final side = moduleSize * (qr.moduleCount + 8);
                final padding = 4 * moduleSize;
                return Center(
                  child: QrImageView.withQr(
                    qr: qr,
                    size: side,
                    padding: EdgeInsets.all(padding),
                    backgroundColor: Colors.white,
                    gapless: true,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    semanticsLabel:
                        'Matter pairing QR. Use Copy code to pair manually.',
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ] else ...[
            const Text('QR unavailable. Use the setup code.'),
            const SizedBox(height: 12),
          ],
          SelectableText(
            code,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy code'),
          ),
          if (qr != null && !enlarged)
            TextButton.icon(
              onPressed: () => showPairingQr(context, session),
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Enlarge QR'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Scan with another phone’s home app, or copy the code to pair on this phone.',
          ),
        ],
      );
    },
  );
}

class _PairingQrDialog extends StatefulWidget {
  const _PairingQrDialog({required this.session});
  final TerminalSession session;
  @override
  State<_PairingQrDialog> createState() => _PairingQrDialogState();
}

class _PairingQrDialogState extends State<_PairingQrDialog> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (widget.session.pairingCode == null && !_closing) {
      _closing = true;
      Future<void>.microtask(() {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        // Background apps stop producing frames. Revoke without waiting for
        // a frame or a pop animation, including under a selection menu.
        if (route?.isActive == true) Navigator.of(context).removeRoute(route!);
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
    child: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pair Door Release',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close pairing QR',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Read current session state, not a captured secret that could go stale.
            PairingCodeDisplay(session: widget.session, enlarged: true),
          ],
        ),
      ),
    ),
  );
}
