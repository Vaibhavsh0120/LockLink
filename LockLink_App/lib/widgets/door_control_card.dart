import 'package:flutter/material.dart';

class DoorControlCard extends StatelessWidget {
  const DoorControlCard({
    super.key,
    required this.online,
    required this.ready,
    required this.active,
    required this.stateLabel,
    required this.statusText,
    required this.helperText,
    required this.onUnlock,
    this.compact = false,
  });

  final bool online;
  final bool ready;
  final bool active;
  final String stateLabel;
  final String statusText;
  final String? helperText;
  final VoidCallback? onUnlock;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final statusColor = dark
        ? (online && ready ? colors.onSurface : colors.onSurfaceVariant)
        : !online
        ? colors.onSurfaceVariant
        : !ready || active
        ? const Color(0xFF805712)
        : const Color(0xFF386446);
    final canUnlock = online && ready && !active && onUnlock != null;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 24 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Front door', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          stateLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: statusText,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 200 : 224),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.outlineVariant),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active
                                    ? colors.primaryContainer
                                    : colors.surface,
                                border: Border.all(
                                  color: colors.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Icon(
                                active
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_outline_rounded,
                                size: compact ? 64 : 72,
                                color: online && ready
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (active)
                          const Positioned.fill(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        Positioned.fill(
                          child: Semantics(
                            button: true,
                            enabled: canUnlock,
                            label: 'Unlock door',
                            value: stateLabel,
                            child: Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: const ValueKey('door-unlock-control'),
                                customBorder: const CircleBorder(),
                                onTap: canUnlock ? onUnlock : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: canUnlock ? onUnlock : null,
              icon: Icon(
                active ? Icons.hourglass_top_rounded : Icons.lock_open_rounded,
                size: 20,
              ),
              label: Text(active ? 'Unlocking…' : 'Unlock door'),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 16),
              Text(
                helperText!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
