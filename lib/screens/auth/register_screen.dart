import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _carModel = TextEditingController();
  final _carPlate = TextEditingController();

  String _role = 'client';
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  bool get _isDriver => _role == 'driver';

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _carModel, _carPlate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;

    String? problem;
    if (name.isEmpty) {
      problem = 'Введите имя';
    } else if (phone.length < 6) {
      problem = 'Введите номер телефона';
    } else if (!email.contains('@')) {
      problem = 'Введите корректный email';
    } else if (pass.length < 6) {
      problem = 'Пароль должен быть не короче 6 символов';
    } else if (_isDriver &&
        (_carModel.text.trim().isEmpty || _carPlate.text.trim().isEmpty)) {
      problem = 'Укажите марку автомобиля и госномер';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signUp(
        email: email,
        password: pass,
        role: _role,
        fullName: name,
        phone: phone,
        carModel: _isDriver ? _carModel.text.trim() : null,
        carPlate: _isDriver ? _carPlate.text.trim() : null,
      );
      // Аккаунт создан и выполнен вход — роутер сам откроет главный экран.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось создать аккаунт. Попробуйте ещё раз.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primaryDark),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Регистрация',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'client',
                          icon: Icon(Icons.person),
                          label: Text('Я пассажир'),
                        ),
                        ButtonSegment(
                          value: 'driver',
                          icon: Icon(Icons.local_taxi),
                          label: Text('Я водитель'),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: (s) =>
                          setState(() => _role = s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(_name, 'Имя', Icons.badge_outlined),
                  const SizedBox(height: 12),
                  _field(_phone, 'Телефон', Icons.phone_outlined,
                      type: TextInputType.phone),
                  if (_isDriver) ...[
                    const SizedBox(height: 12),
                    _field(_carModel, 'Марка и цвет авто',
                        Icons.directions_car_outlined),
                    const SizedBox(height: 12),
                    _field(_carPlate, 'Госномер', Icons.pin_outlined),
                  ],
                  const SizedBox(height: 12),
                  _field(_email, 'Email', Icons.email_outlined,
                      type: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: _decoration('Пароль', Icons.lock_outline)
                        .copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Создать аккаунт'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? type}) {
    return TextField(
      controller: c,
      keyboardType: type,
      decoration: _decoration(label, icon),
    );
  }
}

InputDecoration _decoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.pink.shade100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.pink.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
