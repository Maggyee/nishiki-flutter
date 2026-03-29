import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';

/// 登录 / 注册底部弹窗
/// 采用邮箱验证码方式，分两步：输入邮箱 → 输入验证码
class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});

  /// 展示登录弹窗的便捷方法
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LoginSheet(),
    );
    return result ?? false;
  }

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet>
    with SingleTickerProviderStateMixin {
  // 当前步骤：0 = 输入邮箱，1 = 输入验证码
  int _step = 0;

  // 控制器
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();

  // 状态
  bool _loading = false;
  String? _errorMessage;
  String _email = '';

  // 倒计时重发验证码
  int _resendCountdown = 0;
  Timer? _resendTimer;

  // 入场动画
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final _authService = AuthService();
  final _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _emailFocusNode.dispose();
    _codeFocusNode.dispose();
    _resendTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  // ==================== 业务逻辑 ====================

  /// 请求发送验证码
  Future<void> _requestCode() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '请输入有效的邮箱地址');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _authService.requestEmailCode(email);
      if (!mounted) return;
      setState(() {
        _email = email;
        _step = 1;
        _loading = false;
        _resendCountdown = 60;
      });
      _startResendTimer();
      // 自动聚焦到验证码输入框
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _codeFocusNode.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 验证验证码
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = '请输入验证码');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _authService.verifyEmailCode(_email, code);
      if (!mounted) return;

      // 登录成功后执行首次同步
      try {
        await _syncService.reconcileLocalState();
        await _syncService.connectRealtime();
      } catch (_) {
        // 同步失败不影响登录成功
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 重发验证码
  Future<void> _resendCode() async {
    if (_resendCountdown > 0) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _authService.requestEmailCode(_email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resendCountdown = 60;
      });
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 启动重发倒计时
  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  /// 返回到邮箱输入步骤
  void _goBack() {
    setState(() {
      _step = 0;
      _errorMessage = null;
      _codeController.clear();
    });
    _resendTimer?.cancel();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _emailFocusNode.requestFocus();
    });
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 考虑键盘弹出时的底部间距
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽指示条
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkModeSecondary.withValues(alpha: 0.4)
                          : AppTheme.dividerStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // 头部图标和标题
                  _buildHeader(isDark),

                  const SizedBox(height: 24),

                  // 根据步骤切换内容（带动画）
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _step == 0
                        ? _buildEmailStep(isDark)
                        : _buildCodeStep(isDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部图标 + 标题
  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        // 渐变图标
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.cloud_sync_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _step == 0 ? '登录以同步数据' : '输入验证码',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _step == 0
              ? '登录后，你的收藏、阅读记录和设置将自动在多设备间同步'
              : '验证码已发送至 $_email',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
          ),
        ),
      ],
    );
  }

  /// 第一步：邮箱输入
  Widget _buildEmailStep(bool isDark) {
    return Column(
      key: const ValueKey('email_step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 邮箱输入框
        TextField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          autofocus: true,
          enabled: !_loading,
          onSubmitted: (_) => _requestCode(),
          decoration: InputDecoration(
            hintText: '请输入你的邮箱',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            suffixIcon: _emailController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _emailController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() => _errorMessage = null),
        ),

        // 错误信息
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          _buildErrorBanner(isDark),
        ],

        const SizedBox(height: 20),

        // 发送验证码按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _loading ? null : _requestCode,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('发送验证码'),
          ),
        ),

        const SizedBox(height: 12),

        // 说明文字
        Text(
          '我们将向你的邮箱发送 6 位数字验证码',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
          ),
        ),
      ],
    );
  }

  /// 第二步：验证码输入
  Widget _buildCodeStep(bool isDark) {
    return Column(
      key: const ValueKey('code_step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 验证码输入框
        TextField(
          controller: _codeController,
          focusNode: _codeFocusNode,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          enabled: !_loading,
          onSubmitted: (_) => _verifyCode(),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
              color: isDark
                  ? AppTheme.darkModeSecondary.withValues(alpha: 0.3)
                  : AppTheme.lightText.withValues(alpha: 0.3),
            ),
            counterText: '', // 隐藏字符计数器
          ),
          onChanged: (value) {
            setState(() => _errorMessage = null);
            // 输入满 6 位自动提交
            if (value.length == 6) {
              _verifyCode();
            }
          },
        ),

        // 错误信息
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          _buildErrorBanner(isDark),
        ],

        const SizedBox(height: 20),

        // 验证按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _loading ? null : _verifyCode,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('验证并登录'),
          ),
        ),

        const SizedBox(height: 12),

        // 底部操作栏：返回 + 重发
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _loading ? null : _goBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('更换邮箱'),
            ),
            TextButton(
              onPressed:
                  _loading || _resendCountdown > 0 ? null : _resendCode,
              child: Text(
                _resendCountdown > 0
                    ? '${_resendCountdown}s 后重发'
                    : '重发验证码',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 错误提示条
  Widget _buildErrorBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
