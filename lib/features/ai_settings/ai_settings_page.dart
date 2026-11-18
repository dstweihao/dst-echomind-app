import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/ai/provider_presets.dart';
import '../../data/updates/update_client.dart';
import '../../data/updates/update_config.dart';
import '../../data/updates/update_installer.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/models/ai_settings.dart';
import '../../domain/models/update_info.dart';
import '../../domain/models/update_status.dart';
import '../../providers.dart';
import '../../router.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/back_leading.dart';
import '../learn/study_chat_controller.dart';

/// 极简设置页：仅保留核心 DeepSeek API/模型配置、语音交互配置，以及版本与作者个人主页信息
class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _apiKey = TextEditingController();
  bool _busy = false;
  bool _obscureKey = true;
  bool _configLoaded = false;
  bool _keyLoaded = false;

  String _selectedModel = 'deepseek-flash';
  bool _enableThinking = false;
  bool _enableWebSearch = true;
  bool _autoPlayTts = false;
  String _ttsVoiceId = 'stella';
  bool _autoSendAfterAsr = true;

  bool _loadingBalance = false;
  bool? _balanceAvailable;
  String _balanceCurrencySymbol = '¥';
  String? _totalBalance;
  String? _grantedBalance;
  String? _toppedUpBalance;
  String? _balanceError;
  bool _checkingUpdate = false;

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final savedKey = ref.watch(aiApiKeyProvider);
    final aiSettings = ref.watch(aiSettingsProvider);
    final appVersion =
        ref.watch(appVersionProvider).value ?? UpdateConfig.fallbackVersion;
    final updateStatus = ref.watch(updateStatusProvider);
    final availableUpdate =
        updateStatus is UpdateAvailable ? updateStatus : null;
    final chatState = ref.watch(studyChatControllerProvider);

    if (!_configLoaded && config.hasValue) {
      _configLoaded = true;
      _selectedModel =
          kDeepSeekModels.any((m) => m.id == aiSettings.model)
              ? aiSettings.model
              : 'deepseek-flash';
      _enableThinking = aiSettings.enableThinking;
      _enableWebSearch = aiSettings.enableWebSearch;
      _autoPlayTts = aiSettings.autoPlayTts;
      _ttsVoiceId = aiSettings.ttsVoiceId;
      _autoSendAfterAsr = aiSettings.autoSendAfterAsr;
    }

    if (!_keyLoaded && savedKey.hasValue) {
      final k = savedKey.value ?? '';
      _apiKey.text = k;
      _keyLoaded = true;
      if (k.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchDeepSeekBalance(k);
        });
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const PageBackButton(fallback: AppRouter.learn),
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '保存',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _buildSectionHeader('模型与密钥', Icons.key_rounded),
            const SizedBox(height: 12),
            _buildKeyAndModelCard(),
            const SizedBox(height: 24),

            _buildSectionHeader('语音', Icons.volume_up_outlined),
            const SizedBox(height: 12),
            _buildVoiceCard(chatState),
            const SizedBox(height: 24),

            _buildSectionHeader('关于', Icons.info_outline_rounded),
            const SizedBox(height: 12),
            _buildAuthorCard(appVersion, availableUpdate),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 1. DeepSeek Key + 最新模型选择
  // ------------------------------------------------------------------

  Widget _buildKeyAndModelCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.key_rounded, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text(
                'DeepSeek API Key',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B42A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedModel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00B42A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildBalanceBar(),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          const Text(
            '模型',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 10),
          ...kDeepSeekModels.map((m) {
            final selected = _selectedModel == m.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedModel = m.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          _buildSwitchRow(
            title: '联网搜索',
            value: _enableWebSearch,
            onChanged: (v) => setState(() => _enableWebSearch = v),
          ),
          if (_selectedModel == 'deepseek-flash') ...[
            const Divider(height: 12, color: Color(0xFFF1F5F9)),
            _buildSwitchRow(
              title: '深度思考',
              value: _enableThinking,
              onChanged: (v) => setState(() => _enableThinking = v),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 2. 语音交互设置（自动播报、音色试听、语音转文字自动发送）
  // ------------------------------------------------------------------

  Widget _buildVoiceCard(StudyChatState chatState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSwitchRow(
            title: '自动播报回复',
            value: _autoPlayTts,
            onChanged: (v) => setState(() => _autoPlayTts = v),
          ),
          const Divider(height: 18, color: Color(0xFFF1F5F9)),
          _buildSwitchRow(
            title: '语音转文字自动发送',
            value: _autoSendAfterAsr,
            onChanged: (v) => setState(() => _autoSendAfterAsr = v),
          ),
          const Divider(height: 18, color: Color(0xFFF1F5F9)),
          const Text(
            '音色',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 10),
          ...kDeepSeekVoices.map((voice) {
            final selected = _ttsVoiceId == voice.id;
            final isPreviewing = chatState.isSpeaking &&
                chatState.playingMessageId == '__preview_${voice.id}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _ttsVoiceId = voice.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          voice.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ctrl =
                              ref.read(studyChatControllerProvider.notifier);
                          if (isPreviewing) {
                            await ctrl.stopPlayback();
                          } else {
                            await ctrl.previewVoice(
                              voice.id,
                              apiKeyOverride: _apiKey.text.trim(),
                            );
                            if (!context.mounted) return;
                            final err =
                                ref.read(studyChatControllerProvider).errorMessage;
                            if (err != null && err.isNotEmpty) {
                              _showCenteredDialog(
                                title: '试听失败',
                                message: err,
                                isError: true,
                              );
                            }
                          }
                        },
                        icon: Icon(
                          isPreviewing
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 16,
                        ),
                        label: Text(isPreviewing ? '停止' : '试听'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 30),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 余额查询
  // ------------------------------------------------------------------

  Future<void> _fetchDeepSeekBalance(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loadingBalance = true;
      _balanceError = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.deepseek.com/user/balance'),
        headers: {
          'Authorization': 'Bearer $key',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final isAvailable = data['is_available'] as bool? ?? false;
        final list = data['balance_infos'] as List<dynamic>?;
        String currencySymbol = '¥';
        String? total;
        String? granted;
        String? toppedUp;
        if (list != null && list.isNotEmpty) {
          final entries = list.whereType<Map<String, dynamic>>().toList();
          final picked = entries.firstWhere(
            (e) => (e['currency']?.toString().toUpperCase() ?? '') == 'CNY',
            orElse: () => entries.first,
          );
          final currency = picked['currency']?.toString().toUpperCase() ?? 'CNY';
          currencySymbol = currency == 'USD' ? r'$' : '¥';
          total = picked['total_balance']?.toString();
          granted = picked['granted_balance']?.toString();
          toppedUp = picked['topped_up_balance']?.toString();
        }

        if (mounted) {
          setState(() {
            _loadingBalance = false;
            _balanceAvailable = isAvailable;
            _balanceCurrencySymbol = currencySymbol;
            _totalBalance = total ?? '0.00';
            _grantedBalance = granted;
            _toppedUpBalance = toppedUp;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loadingBalance = false;
            _balanceError = '查询失败 (HTTP ${response.statusCode})';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingBalance = false;
          _balanceError = '网络或密钥异常';
        });
      }
    }
  }

  Widget _buildBalanceBar() {
    if (_loadingBalance) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              '正在查询 DeepSeek 实时额度…',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    if (_balanceError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _balanceError!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
              ),
            ),
            InkWell(
              onTap: () => _fetchDeepSeekBalance(_apiKey.text.trim()),
              child: const Text(
                '重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_totalBalance == null && _balanceAvailable == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onTap: () => _fetchDeepSeekBalance(_apiKey.text.trim()),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '查询余额',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isAvailable = _balanceAvailable == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAvailable
                  ? const Color(0xFF00B42A)
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isAvailable ? '可用' : '耗尽',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isAvailable
                  ? const Color(0xFF00B42A)
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: '$_balanceCurrencySymbol ${_totalBalance ?? "0.00"} ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
                children: [
                  if (_toppedUpBalance != null || _grantedBalance != null)
                    TextSpan(
                      text:
                          '(充值 $_balanceCurrencySymbol${_toppedUpBalance ?? "0"} · 赠送 $_balanceCurrencySymbol${_grantedBalance ?? "0"})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () => _fetchDeepSeekBalance(_apiKey.text.trim()),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.refresh_rounded,
                size: 15,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 保存逻辑
  // ------------------------------------------------------------------

  AiSettings _buildSettings() {
    final preset = presetById('deepseek');
    return AiSettings(
      enabled: true,
      protocol: preset?.protocol ?? AiProtocol.openai,
      baseUrl: preset?.baseUrl ?? 'https://api.deepseek.com',
      model: _selectedModel,
      maxTokens: 4096,
      reasoningEffort: 'high',
      enableThinking: _enableThinking,
      enableWebSearch: _enableWebSearch,
      timeoutSeconds: 120,
      persona: 'study_mode_socratic',
      autoPlayTts: _autoPlayTts,
      ttsVoiceId: _ttsVoiceId,
      autoSendAfterAsr: _autoSendAfterAsr,
    );
  }

  Future<void> _save() async {
    final key = _apiKey.text.trim();
    if (key.isEmpty) {
      _showCenteredDialog(
        title: '提示',
        message: '请先输入有效的 API Key',
        isError: true,
      );
      return;
    }

    setState(() => _busy = true);

    try {
      await ref.read(secretStoreProvider).saveAiApiKey(key);
      try {
        await ref.read(configRepositoryProvider).saveAiSettings(_buildSettings());
      } catch (e) {
        debugPrint('Config save warning: $e');
      }

      ref
        ..invalidate(appConfigProvider)
        ..invalidate(aiApiKeyProvider);

      if (!mounted) return;
      AppToast.showSuccess(
        context,
        title: '保存成功',
        detail: 'DeepSeek 模型与语音配置已生效',
      );
      _fetchDeepSeekBalance(key);
    } catch (e) {
      if (!mounted) return;
      _showCenteredDialog(
        title: '保存失败',
        message: '保存出错：$e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // 3. 关于、版本更新与作者个人主页（完整保留）
  // ------------------------------------------------------------------

  Widget _buildAuthorCard(String version, UpdateAvailable? availableUpdate) {
    final hasUpdate = availableUpdate != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const AppLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      AppIdentity.appName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v$version',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: OutlinedButton(
                  onPressed: _checkingUpdate
                      ? null
                      : () {
                          if (hasUpdate) {
                            _showUpdateDialog(
                              availableUpdate.currentVersion,
                              availableUpdate.release,
                            );
                          } else {
                            _handleCheckUpdate();
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(
                      color: hasUpdate
                          ? AppColors.primary.withValues(alpha: 0.45)
                          : const Color(0xFFE2E8F0),
                    ),
                    backgroundColor: hasUpdate
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  child: _checkingUpdate
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasUpdate) ...[
                              Container(
                                key: const Key('settings_update_badge_dot'),
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              hasUpdate
                                  ? '发现 ${availableUpdate.release.tagName}'
                                  : '检查更新',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          _buildInfoRow(
            label: 'GitHub',
            value: 'github.com/dstweihao',
            copyContent: 'https://github.com/dstweihao',
            onTap: () => _openUrl('https://github.com/dstweihao'),
          ),
          const Divider(height: 14, color: Color(0xFFF8FAFC)),
          _buildInfoRow(
            label: '个人网站',
            value: 'https://dstweihao.cn',
            copyContent: 'https://dstweihao.cn',
            onTap: () => _openUrl('https://dstweihao.cn'),
          ),
          const Divider(height: 14, color: Color(0xFFF8FAFC)),
          _buildInfoRow(
            label: '微信公众号',
            value: '码上生长',
            copyContent: '码上生长',
            onTap: () => _copyText('码上生长', '已复制微信公众号：码上生长'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    String? copyContent,
    VoidCallback? onTap,
  }) {
    final toCopy = copyContent ?? value;
    return InkWell(
      onTap: onTap,
      onLongPress: () => _copyText(toCopy, '已复制 $label：$toCopy'),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF1E293B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Future<void> _handleCheckUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    try {
      await ref.read(updateStatusProvider.notifier).check();
      if (!mounted) return;
      setState(() => _checkingUpdate = false);

      final status = ref.read(updateStatusProvider);
      switch (status) {
        case UpdateAvailable(:final currentVersion, :final release):
          _showUpdateDialog(currentVersion, release);
        case UpdateUpToDate(:final currentVersion):
          _showCenteredDialog(
            title: '检查更新',
            message: '当前已是最新版本 (v$currentVersion)',
          );
        case UpdateCheckFailed(:final message):
          _showCenteredDialog(
            title: '检查更新失败',
            message: message,
            isError: true,
          );
        case UpdateIdle():
        case UpdateChecking():
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
      _showCenteredDialog(
        title: '检查更新失败',
        message: e is UpdateException ? e.message : '网络或服务异常：$e',
        isError: true,
      );
    }
  }

  void _showUpdateDialog(String current, ReleaseInfo release) {
    final matchedAsset = selectCurrentPlatformAsset(release);
    final assetSizeBytes = matchedAsset?.size ?? 0;

    bool downloading = false;
    bool cancelledByUser = false;
    bool needsPermission = false;
    double? downloadProgress;
    int receivedBytes = 0;
    int? totalBytes = assetSizeBytes > 0 ? assetSizeBytes : null;
    String? errorMsg;
    String? permissionMsg;
    http.Client? activeClient;

    String formatMb(int bytes) {
      if (bytes <= 0) return '0 MB';
      final mb = bytes / (1024 * 1024);
      return mb >= 10
          ? '${mb.toStringAsFixed(1)} MB'
          : '${mb.toStringAsFixed(2)} MB';
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> startInstall() async {
            final client = http.Client();
            activeClient = client;
            cancelledByUser = false;
            setDialogState(() {
              downloading = true;
              errorMsg = null;
              permissionMsg = null;
              downloadProgress = null;
              receivedBytes = 0;
              totalBytes = assetSizeBytes > 0 ? assetSizeBytes : null;
            });

            try {
              final installer = ref.read(updateInstallerProvider);
              final result = await installer(
                release,
                httpClient: client,
                onProgress: (p) {
                  if (dialogCtx.mounted && !cancelledByUser) {
                    setDialogState(() => downloadProgress = p);
                  }
                },
                onBytesProgress: (received, total) {
                  if (dialogCtx.mounted && !cancelledByUser) {
                    setDialogState(() {
                      receivedBytes = received;
                      if (total != null && total > 0) totalBytes = total;
                    });
                  }
                },
              );

              if (cancelledByUser) return;

              if (result.outcome == InstallOutcome.needsPermission) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    downloading = false;
                    needsPermission = true;
                    permissionMsg = result.message;
                  });
                }
                return;
              }

              if (!result.isSuccess) {
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    downloading = false;
                    errorMsg = result.message;
                  });
                }
                return;
              }

              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
              if (mounted) {
                AppToast.showSuccess(
                  this.context,
                  title: result.outcome == InstallOutcome.launched
                      ? '安装包已就绪'
                      : '已打开下载页面',
                  detail: result.message.isNotEmpty
                      ? result.message
                      : (result.outcome == InstallOutcome.launched
                          ? '请按提示完成更新'
                          : null),
                );
              }
            } catch (e) {
              if (!cancelledByUser && dialogCtx.mounted) {
                setDialogState(() {
                  downloading = false;
                  errorMsg = '下载安装失败：$e';
                });
              }
            } finally {
              if (identical(activeClient, client)) {
                activeClient = null;
              }
              client.close();
            }
          }

          void cancelDownload() {
            cancelledByUser = true;
            activeClient?.close();
            activeClient = null;
            if (dialogCtx.mounted) {
              setDialogState(() {
                downloading = false;
                downloadProgress = null;
                receivedBytes = 0;
              });
            }
          }

          final fallbackUrl = matchedAsset?.browserDownloadUrl.isNotEmpty == true
              ? matchedAsset!.browserDownloadUrl
              : release.htmlUrl;

          final primaryLabel = needsPermission
              ? '立即安装'
              : (errorMsg != null ? '重试下载' : '立即更新');

          return PopScope(
            canPop: !downloading,
            child: Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部标题与版本胶囊
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '发现新版本 ${release.tagName}',
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        'v$current',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 13,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        release.tagName,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    if (assetSizeBytes > 0)
                                      Text(
                                        '· ${formatMb(assetSizeBytes)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // 更新内容（Markdown 渲染，告别 ### / ** 源码）
                      if (release.notes.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 240),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context)
                                .copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              child: MarkdownBody(
                                data: release.notes.trim(),
                                shrinkWrap: true,
                                styleSheet: MarkdownStyleSheet(
                                  h1: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                    height: 1.4,
                                  ),
                                  h2: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                    height: 1.4,
                                  ),
                                  h3: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                    height: 1.4,
                                  ),
                                  h3Padding:
                                      const EdgeInsets.only(top: 6, bottom: 4),
                                  p: const TextStyle(
                                    fontSize: 12.8,
                                    color: Color(0xFF334155),
                                    height: 1.55,
                                  ),
                                  strong: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  listBullet: TextStyle(
                                    fontSize: 12.8,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  listIndent: 16,
                                  blockSpacing: 8,
                                  code: const TextStyle(
                                    fontSize: 11.8,
                                    color: Color(0xFF1E293B),
                                    backgroundColor: Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // 应用内实时下载进度条
                      if (downloading) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      downloadProgress != null
                                          ? '正在下载安装包…'
                                          : '正在连接下载源…',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  if (downloadProgress != null)
                                    Text(
                                      '${(downloadProgress! * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: downloadProgress,
                                  minHeight: 7,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                              if (receivedBytes > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  totalBytes != null && totalBytes! > 0
                                      ? '${formatMb(receivedBytes)} / ${formatMb(totalBytes!)}'
                                      : '已下载 ${formatMb(receivedBytes)}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // Android 未知来源授权指引
                      if (permissionMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFFD97706),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  permissionMsg!,
                                  style: const TextStyle(
                                    fontSize: 12.2,
                                    color: Color(0xFF92400E),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 下载失败提示 + 仅失败时提供的直链兜底
                      if (errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFECACA),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                errorMsg!,
                                style: const TextStyle(
                                  fontSize: 12.2,
                                  color: Color(0xFFDC2626),
                                  height: 1.4,
                                ),
                              ),
                              if (fallbackUrl.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _openUrl(fallbackUrl),
                                  child: Text(
                                    '网络较慢？点此通过浏览器直接下载安装包',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // 底部操作区
                      const SizedBox(height: 18),
                      if (downloading)
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton(
                            onPressed: cancelDownload,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: const Text(
                              '取消下载',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(),
                                  style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF475569),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                  child: const Text(
                                    '稍后再说',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: startInstall,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    primaryLabel,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCenteredDialog({
    required String title,
    required String message,
    bool isError = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isError
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFDCFCE7),
                ),
                child: Icon(
                  isError ? Icons.error_outline_rounded : Icons.check_rounded,
                  size: 26,
                  color: isError
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isError
                        ? const Color(0xFFEF4444)
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '知道了',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyText(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppToast.showCopied(context, message: tip);
  }
}
