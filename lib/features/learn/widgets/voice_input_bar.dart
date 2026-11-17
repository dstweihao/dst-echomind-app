import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../study_chat_controller.dart';

/// 参照豆包 / DeepSeek / 微信打造的语音 + 打字双模式输入栏
///
/// - 左侧按钮在「打字模式」与「语音模式」间一键切换；
/// - 语音模式下居中为宽大「按住说话」胶囊：
///   * 按下 0ms 即刻开录（不吞开头字）；
///   * 按住不放持续收音并展示实时声波与计时；
///   * 上滑超过 56px 平滑切换为红色「松开取消」态；
///   * 正常松手立即交由 DeepSeek ASR 转文字并发送。
class VoiceInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final VoiceInputPhase voicePhase;
  final double recordingAmplitude;
  final Duration recordingDuration;
  final VoidCallback onSendText;
  final VoidCallback onCancelGeneration;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final ValueChanged<String> onTextChanged;

  const VoiceInputBar({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.voicePhase,
    required this.recordingAmplitude,
    required this.recordingDuration,
    required this.onSendText,
    required this.onCancelGeneration,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onTextChanged,
  });

  @override
  State<VoiceInputBar> createState() => _VoiceInputBarState();
}

class _VoiceInputBarState extends State<VoiceInputBar> {
  static const double _cancelDragThreshold = 56.0;

  bool _voiceMode = false;
  bool _pointerHolding = false;
  bool _inCancelZone = false;
  int? _activePointer;
  double _pressStartGlobalY = 0.0;

  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (widget.isGenerating ||
        widget.voicePhase != VoiceInputPhase.idle) {
      return;
    }
    setState(() {
      _voiceMode = !_voiceMode;
      _pointerHolding = false;
      _inCancelZone = false;
    });
    if (_voiceMode) {
      _focusNode.unfocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.isGenerating ||
        widget.voicePhase != VoiceInputPhase.idle ||
        _pointerHolding) {
      return;
    }
    _activePointer = event.pointer;
    _pressStartGlobalY = event.position.dy;
    setState(() {
      _pointerHolding = true;
      _inCancelZone = false;
    });
    HapticFeedback.mediumImpact();
    widget.onStartRecording();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointerHolding || event.pointer != _activePointer) return;
    final dyUp = _pressStartGlobalY - event.position.dy;
    final shouldCancel = dyUp >= _cancelDragThreshold;
    if (shouldCancel != _inCancelZone) {
      HapticFeedback.lightImpact();
      setState(() => _inCancelZone = shouldCancel);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_pointerHolding || event.pointer != _activePointer) return;
    final shouldCancel = _inCancelZone;
    _activePointer = null;
    setState(() {
      _pointerHolding = false;
      _inCancelZone = false;
    });

    if (shouldCancel) {
      widget.onCancelRecording();
    } else {
      widget.onStopRecording();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!_pointerHolding || event.pointer != _activePointer) return;
    _activePointer = null;
    setState(() {
      _pointerHolding = false;
      _inCancelZone = false;
    });
    widget.onCancelRecording();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording =
        widget.voicePhase == VoiceInputPhase.recording || _pointerHolding;
    final isTranscribing = widget.voicePhase == VoiceInputPhase.transcribing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRecording) _buildRecordingOverlayBanner(),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isRecording
                  ? (_inCancelZone
                      ? AppColors.danger.withValues(alpha: 0.6)
                      : AppColors.primary.withValues(alpha: 0.55))
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: isTranscribing
              ? _buildTranscribingRow()
              : _voiceMode
                  ? _buildVoiceModeRow(isRecording)
                  : _buildTextModeRow(),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 录音浮层提示（类似豆包 / DeepSeek 上滑取消指示条）
  // ------------------------------------------------------------------

  Widget _buildRecordingOverlayBanner() {
    final secs = widget.recordingDuration.inSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final accent = _inCancelZone ? AppColors.danger : AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _inCancelZone ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _inCancelZone ? Icons.delete_outline_rounded : Icons.mic_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                '$mm:$ss',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LiveWaveform(
                  amplitude: widget.recordingAmplitude,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _inCancelZone ? '松开手指，取消发送' : '松开发送，上滑取消',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _inCancelZone ? AppColors.danger : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 语音模式：左侧切键盘 + 中间「按住说话」整条按压胶囊
  // ------------------------------------------------------------------

  Widget _buildVoiceModeRow(bool isRecording) {
    final bgColor = isRecording
        ? (_inCancelZone
            ? AppColors.danger.withValues(alpha: 0.14)
            : AppColors.primary)
        : const Color(0xFFF1F5F9);

    final fgColor = isRecording
        ? (_inCancelZone ? AppColors.danger : Colors.white)
        : const Color(0xFF1E293B);

    final label = isRecording
        ? (_inCancelZone ? '松开取消' : '松开发送')
        : '按住 说话';

    return Row(
      children: [
        _modeToggleButton(
          icon: Icons.keyboard_alt_outlined,
          tooltip: '切换为打字输入',
          disabled: isRecording || widget.isGenerating,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.isGenerating
                    ? const Color(0xFFF8FAFC)
                    : bgColor,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isRecording
                        ? (_inCancelZone
                            ? Icons.close_rounded
                            : Icons.graphic_eq_rounded)
                        : Icons.mic_rounded,
                    size: 18,
                    color: widget.isGenerating
                        ? const Color(0xFF94A3B8)
                        : fgColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isGenerating ? '回复生成中…' : label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: widget.isGenerating
                          ? const Color(0xFF94A3B8)
                          : fgColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.isGenerating) ...[
          const SizedBox(width: 8),
          _stopGenerationButton(),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // 打字模式：左侧切语音 + 中间输入框 + 右侧发送/停止
  // ------------------------------------------------------------------

  Widget _buildTextModeRow() {
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _modeToggleButton(
          icon: Icons.mic_none_rounded,
          tooltip: '切换为按住说话（语音模式）',
          disabled: widget.isGenerating,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: !widget.isGenerating,
            style: const TextStyle(fontSize: 15.5, height: 1.45),
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            textAlignVertical: TextAlignVertical.center,
            decoration: const InputDecoration(
              hintText: '问点什么…',
              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            ),
            onSubmitted: (_) => widget.onSendText(),
            onChanged: widget.onTextChanged,
          ),
        ),
        const SizedBox(width: 8),
        if (widget.isGenerating)
          _stopGenerationButton()
        else
          InkWell(
            onTap: hasText ? widget.onSendText : null,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasText ? AppColors.primary : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: hasText ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _modeToggleButton({
    required IconData icon,
    required String tooltip,
    required bool disabled,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: disabled ? null : _toggleMode,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFF1F5F9)
                : AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled ? const Color(0xFFCBD5E1) : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _stopGenerationButton() {
    return InkWell(
      onTap: widget.onCancelGeneration,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.stop_rounded,
          size: 20,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTranscribingRow() {
    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            '转写中…',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveWaveform extends StatelessWidget {
  final double amplitude;
  final Color color;

  const _LiveWaveform({
    required this.amplitude,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const barCount = 16;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(barCount, (i) {
        final centerWeight =
            1.0 - ((i - (barCount - 1) / 2).abs() / (barCount / 2));
        final wave = math.sin((i + 1) * 0.9).abs();
        final h = 6.0 +
            (22.0 *
                (0.2 + amplitude * 0.8) *
                (0.45 + 0.55 * centerWeight) *
                (0.6 + 0.4 * wave));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 3,
          height: h.clamp(5.0, 26.0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
