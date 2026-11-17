import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../study_chat_controller.dart';

/// 播报中悬浮状态条：展示当前音色正在朗读，支持一键随时打断
class TtsStatusPill extends StatelessWidget {
  final TtsPlaybackPhase phase;
  final String voiceName;
  final VoidCallback onStop;

  const TtsStatusPill({
    super.key,
    required this.phase,
    required this.voiceName,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    if (phase == TtsPlaybackPhase.idle) return const SizedBox.shrink();

    final isConnecting = phase == TtsPlaybackPhase.connecting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConnecting)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              const SizedBox(width: 8),
              Text(
                isConnecting ? '连接中…' : '朗读中',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: onStop,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_rounded,
                        size: 14,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '停止',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
