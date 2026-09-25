import 'package:flutter/material.dart';

class DoorControlCard extends StatelessWidget {
  const DoorControlCard({
    super.key,
    required this.online,
    required this.active,
    required this.configured,
    required this.stateLabel,
    required this.statusText,
    required this.onUnlock,
    this.compact = false,
  });

  final bool online;
  final bool active;
  final bool configured;
  final String stateLabel;
  final String statusText;
  final VoidCallback? onUnlock;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ringColor = !online
        ? colors.outline
        : active
        ? const Color(0xFFD8AF66)
        : const Color(0xFF80B98B);
    final size = compact ? 208.0 : 236.0;
    final innerSize = size - 22;
    final helperText = !configured
        ? 'Add your device address to begin'
        : online
        ? null
        : 'Check Wi-Fi and device';

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 28),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: ringColor.withValues(alpha: online ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: ringColor),
                    const SizedBox(width: 7),
                    Text(
                      statusText,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ringColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: compact ? 28 : 36),
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 3),
                    ),
                  ),
                  if (active)
                    SizedBox(
                      width: size,
                      height: size,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: ringColor,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  SizedBox(
                    width: innerSize,
                    height: innerSize,
                    child: FilledButton(
                      onPressed: online && !active ? onUnlock : null,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor: colors.surfaceContainerHighest,
                        disabledForegroundColor: colors.onSurfaceVariant,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              active
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_rounded,
                              key: ValueKey(active),
                              size: compact ? 52 : 62,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            active ? 'UNLOCKING' : 'UNLOCK',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: online && !active
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 24 : 30),
            Text(
              stateLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 6),
              Text(
                helperText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
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
