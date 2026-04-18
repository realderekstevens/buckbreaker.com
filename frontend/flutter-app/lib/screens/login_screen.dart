import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _loginKey    = GlobalKey<FormState>();
  final _registerKey = GlobalKey<FormState>();

  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl  = TextEditingController();
  final _regNameCtrl  = TextEditingController();

  bool _loading  = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose();
    _regEmailCtrl.dispose(); _regPassCtrl.dispose(); _regNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_loginKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthService>().login(
        _emailCtrl.text.trim(), _passCtrl.text,
      );
      widget.onSuccess();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (!(_registerKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      await auth.register(
        _regEmailCtrl.text.trim(), _regPassCtrl.text,
        displayName: _regNameCtrl.text.trim().isEmpty ? null : _regNameCtrl.text.trim(),
      );
      await auth.login(_regEmailCtrl.text.trim(), _regPassCtrl.text);
      widget.onSuccess();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(children: [
              // Logo / title
              const SizedBox(height: 32),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.gold],
                ).createShader(b),
                child: const Text('TraderDude',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -1)),
              ),
              const SizedBox(height: 6),
              Text('Patrician III  ·  Stock Forecast',
                style: AppTextStyles.monoSm.copyWith(color: AppColors.text3)),
              const SizedBox(height: 40),

              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color:        AppColors.bg2,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabs,
                  indicator: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.border2),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor:   AppColors.accent,
                  unselectedLabelColor: AppColors.text2,
                  tabs: const [Tab(text: 'Sign In'), Tab(text: 'Register')],
                ),
              ),
              const SizedBox(height: 24),

              // Tab content
              SizedBox(
                height: 320,
                child: TabBarView(
                  controller: _tabs,
                  children: [_buildLoginForm(), _buildRegisterForm()],
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        AppColors.neg.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(color: AppColors.neg.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.neg, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: TextStyle(color: AppColors.neg, fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 24),
              // Anonymous continue
              TextButton(
                onPressed: widget.onSuccess,
                child: Text('Continue without signing in  →',
                  style: AppTextStyles.monoSm.copyWith(color: AppColors.text3)),
              ),
            ]),
          ),
        ),
      ),
    ),
  );

  Widget _buildLoginForm() => Form(
    key: _loginKey,
    child: Column(children: [
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: AppTextStyles.mono.copyWith(fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Email', hintText: 'you@example.com',
          prefixIcon: Icon(Icons.email_outlined, size: 18),
        ),
        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passCtrl,
        obscureText: _obscure1,
        style: AppTextStyles.mono.copyWith(fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline, size: 18),
          suffixIcon: IconButton(
            icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility, size: 18),
            onPressed: () => setState(() => _obscure1 = !_obscure1),
          ),
        ),
        validator: (v) => (v == null || v.length < 6) ? 'Password required' : null,
        onFieldSubmitted: (_) => _login(),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Sign In'),
        ),
      ),
    ]),
  );

  Widget _buildRegisterForm() => Form(
    key: _registerKey,
    child: Column(children: [
      TextFormField(
        controller: _regEmailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: AppTextStyles.mono.copyWith(fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, size: 18),
        ),
        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _regNameCtrl,
        style: AppTextStyles.mono.copyWith(fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Display Name (optional)',
          prefixIcon: Icon(Icons.person_outline, size: 18),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _regPassCtrl,
        obscureText: _obscure2,
        style: AppTextStyles.mono.copyWith(fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Password (min 8 chars)',
          prefixIcon: const Icon(Icons.lock_outline, size: 18),
          suffixIcon: IconButton(
            icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility, size: 18),
            onPressed: () => setState(() => _obscure2 = !_obscure2),
          ),
        ),
        validator: (v) => (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _register,
          child: _loading
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Create Account'),
        ),
      ),
    ]),
  );
}
