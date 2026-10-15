import 'package:flutter/material.dart';
import 'package:pcos_app/services/account_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_sent) {
        await AccountService.instance
            .resetPassword(_code.text.trim(), _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Password updated. Sign in with your new password.')));
        Navigator.of(context).pop();
      } else {
        await AccountService.instance.requestPasswordReset(_email.text.trim());
        if (mounted) setState(() => _sent = true);
      }
    } on AccountException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Unable to connect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_sent
                          ? 'If that account exists, a recovery code has been requested. Check your email and paste the code below. It expires after 20 minutes.'
                          : 'Enter the email address you used to create your account.'),
                      const SizedBox(height: 20),
                      if (!_sent)
                        TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                const InputDecoration(labelText: 'Email'),
                            validator: (value) =>
                                value != null && value.contains('@')
                                    ? null
                                    : 'Enter your email address.'),
                      if (_sent) ...[
                        TextFormField(
                            controller: _code,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'Recovery code'),
                            validator: (value) => (value?.trim().length ?? 0) >=
                                    40
                                ? null
                                : 'Paste the complete code from your email.'),
                        TextFormField(
                            controller: _password,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'New password'),
                            validator: (value) => value != null &&
                                    value.length >= 8 &&
                                    value.length <= 128
                                ? null
                                : 'Use 8–128 characters.'),
                        TextFormField(
                            controller: _confirmation,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'Confirm new password'),
                            validator: (value) => value == _password.text
                                ? null
                                : 'Passwords do not match.'),
                      ],
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy
                              ? 'Please wait...'
                              : _sent
                                  ? 'Save new password'
                                  : 'Email recovery code')),
                      if (!_sent)
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _sent = true),
                            child:
                                const Text('I already have a recovery code')),
                    ])),
          ),
        )),
      );
}
