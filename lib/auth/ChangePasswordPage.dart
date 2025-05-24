// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  _ChangePasswordPageState createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool hasUppercase = false;
  bool hasLowercase = false;
  bool hasDigit = false;
  bool hasSpecialChar = false;
  bool hasMinLength = false;

  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';

  void _validatePassword(String password) {
    hasUppercase = password.contains(RegExp(r'[A-Z]'));
    hasLowercase = password.contains(RegExp(r'[a-z]'));
    hasDigit = password.contains(RegExp(r'[0-9]'));
    hasSpecialChar = password.contains(RegExp(r'[!@#\$&*~]'));
    hasMinLength = password.length >= 6;

    int strength = 0;
    if (hasUppercase) strength++;
    if (hasLowercase) strength++;
    if (hasDigit) strength++;
    if (hasSpecialChar) strength++;
    if (hasMinLength) strength++;

    setState(() {
      _passwordStrength = strength / 5; // 5 max
      if (_passwordStrength <= 0.3) {
        _passwordStrengthLabel = 'Weak Password';
      } else if (_passwordStrength <= 0.7) {
        _passwordStrengthLabel = 'Fair Password';
      } else {
        _passwordStrengthLabel = 'Strong Password';
      }
    });
  }

  Future<void> _changePassword() async {
    if (!mounted) return;
    final currentContext = context;

    if (!_formKey.currentState!.validate()) return;

    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      final cred = EmailAuthProvider.credential(
        email: user!.email!,
        password: _currentPasswordController.text.trim(),
      );

      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_passwordController.text.trim());

      if (!mounted) return;
      Navigator.of(currentContext).pop(); // close loading

      _showSuccessDialog(); // show stay/log out options
    } catch (e) {
      if (!mounted) return;
      Navigator.of(currentContext).pop(); // close loading

      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to change password. Please check your current password.',
            style: TextStyle(
              color: Theme.of(currentContext).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(currentContext).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Password Changed'),
          content: const Text('Do you want to stay logged in or sign out?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // back to settings page
              },
              child: const Text('Stay Logged In'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(context).pop(); // close dialog
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChecklistItem(String text, bool condition) {
    return Row(
      children: [
        Icon(
          condition ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: condition ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Color _getStrengthColor() {
    if (_passwordStrength <= 0.3) {
      return Colors.red;
    } else if (_passwordStrength <= 0.7) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Icon(Icons.lock_outline, size: 70, color: Colors.blue),
              const SizedBox(height: 20),

              // Current Password
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscureCurrentPassword,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: 'Current Password',
                  labelStyle: const TextStyle(fontSize: 14),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrentPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () =>
                              _obscureCurrentPassword =
                                  !_obscureCurrentPassword,
                        ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // New Password
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: 'New Password',
                  labelStyle: const TextStyle(fontSize: 14),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
                onChanged: _validatePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a new password';
                  }
                  if (!hasUppercase ||
                      !hasLowercase ||
                      !hasDigit ||
                      !hasSpecialChar ||
                      !hasMinLength) {
                    return 'Please meet all password requirements';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // Password Strength Meter
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _passwordStrength,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getStrengthColor(),
                    ),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _passwordStrengthLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _getStrengthColor(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Password Requirements
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChecklistItem('At least 6 characters', hasMinLength),
                  _buildChecklistItem('1 uppercase letter', hasUppercase),
                  _buildChecklistItem('1 lowercase letter', hasLowercase),
                  _buildChecklistItem('1 number', hasDigit),
                  _buildChecklistItem(
                    '1 special character (!@#\$&*~)',
                    hasSpecialChar,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Confirm Password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  labelText: 'Confirm Password',
                  labelStyle: const TextStyle(fontSize: 14),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                        ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              // Submit Button
              ElevatedButton.icon(
                onPressed: _changePassword,
                icon: const Icon(Icons.lock_open),
                label: const Text('Change Password'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
