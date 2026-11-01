import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/sync/server_action_queue.dart';
import '../../core/theme/text_styles.dart';

/// Small "Cancelling…" / "Deleting…" tag for something waiting on the server,
/// or the server's reason if it said no. Shows nothing when nothing is
/// pending for [targetId]. Never blocks anything.
class ServerActionTag extends StatelessWidget {
  final String targetId;

  const ServerActionTag({super.key, required this.targetId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ServerAction>>(
      valueListenable: ServerActionQueue.instance.actions,
      builder: (context, _, _) {
        final action = ServerActionQueue.instance.forTarget(targetId);
        if (action == null) return const SizedBox.shrink();
        final failed = action.isFailed;
        final color = failed ? AppColors.danger : AppColors.primary;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed)
                Icon(Icons.error_outline, size: 14, color: color)
              else
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  failed
                      ? 'Not done: ${action.lastError ?? 'the server refused'}'
                      : action.label,
                  key: const Key('server_action_tag'),
                  style: AppTextStyles.hint.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
