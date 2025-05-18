import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'EmailVerification.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  static const String _usersCollection = 'users';
  static const String _termsUrl = 'https://tinyurl.com/pencraftpro';
  static const String _supportEmail = 'pencraftpro1@gmail.com';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _isLoading = false;
  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;
  bool _hasMinLength = false;

  @override
  void initState() {
    super.initState();
    // Autofocus email field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (_formKey.currentState!.validate()) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please accept the Terms & Conditions.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return;
      }

      FocusScope.of(context).unfocus();
      setState(() {
        _isLoading = true;
      });

      try {
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim().toLowerCase(),
              password: _passwordController.text.trim(),
            );

        final user = userCredential.user;
        if (user == null) {
          throw Exception('User creation failed: No user object returned.');
        }

        print('Attempting to write user data for UID: ${user.uid}');
        final userDoc =
            await FirebaseFirestore.instance
                .collection(_usersCollection)
                .doc(user.uid)
                .get();

        if (!userDoc.exists) {
          await FirebaseFirestore.instance
              .collection(_usersCollection)
              .doc(user.uid)
              .set({
                'email':
                    user.email ?? _emailController.text.trim().toLowerCase(),
                'fullName': '',
                'role': '',
                'idNumber': '',
                'photoUrl': '',
                'createdAt': FieldValue.serverTimestamp(),
              });
          print(
            'User data successfully written to Firestore for UID: ${user.uid}',
          );
        } else {
          print('User document already exists for UID: ${user.uid}');
        }

        await user.sendEmailVerification();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const EmailVerification()),
        );
      } catch (e) {
        String errorMessage = 'Sign-up failed. Please try again.';
        if (e is FirebaseAuthException) {
          switch (e.code) {
            case 'email-already-in-use':
              errorMessage =
                  'This email is already registered. Try signing in.';
              break;
            case 'invalid-email':
              errorMessage = 'Invalid email format.';
              break;
            case 'weak-password':
              errorMessage = 'Password is too weak.';
              break;
          }
        } else {
          errorMessage = e.toString();
        }
        print('Sign-up error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$errorMessage.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(
                  child: Text(
                    'PenCraft Pro - Terms & Conditions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('1. Respectful Content'),
                const Text(
                  'Please ensure your writing does not include hate speech, harassment, or discrimination.',
                ),
                const SizedBox(height: 8),
                const Text('2. Intellectual Property'),
                const Text(
                  'Users retain ownership of their content, but give PenCraft Pro permission to host it.',
                ),
                const SizedBox(height: 8),
                const Text('3. Account Security'),
                const Text(
                  'Keep your login credentials confidential and secure.',
                ),
                const SizedBox(height: 8),
                const Text('4. Fair Use Policy'),
                const Text(
                  "Don't abuse system resources (e.g., spamming, overloading servers).",
                ),
                const SizedBox(height: 8),
                const Text('5. Data Privacy'),
                const Text(
                  "We don't sell your data. Everything is stored securely and confidentially.",
                ),
                const SizedBox(height: 8),
                const Text('6. Updates & Changes'),
                const Text(
                  "We may modify the terms; we'll notify users of major changes.",
                ),
                const SizedBox(height: 8),
                const Text('7. Third-Party Integrations'),
                const Text('PenCraft Pro may integrate with trusted partners.'),
                const SizedBox(height: 8),
                const Text('8. Termination'),
                const Text(
                  "Violation of terms may result in suspension or deletion of your account.",
                ),
                const SizedBox(height: 8),
                const Text('9. Limitation of Liability'),
                const Text(
                  "We do our best, but we're not liable for data loss or service issues.",
                ),
                const SizedBox(height: 8),
                const Text('10. Contact & Support'),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                    children: [
                      const TextSpan(text: '👉 '),
                      TextSpan(
                        text: '$_termsUrl\n',
                        style: const TextStyle(color: Colors.blue),
                        recognizer:
                            TapGestureRecognizer()
                              ..onTap = () async {
                                final url = Uri.parse(_termsUrl);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                      ),
                      const TextSpan(text: '📧 '),
                      TextSpan(
                        text: _supportEmail,
                        style: const TextStyle(color: Colors.blue),
                        recognizer:
                            TapGestureRecognizer()
                              ..onTap = () async {
                                final emailUri = Uri(
                                  scheme: 'mailto',
                                  path: _supportEmail,
                                  query: 'subject=PenCraft Support',
                                );
                                if (await canLaunchUrl(emailUri)) {
                                  await launchUrl(emailUri);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChecklistItem(String text, bool valid) {
    return Semantics(
      label: valid ? '$text: met' : '$text: not met',
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle : Icons.cancel,
            color: valid ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  void _validatePasswordStrength(String password) {
    setState(() {
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#\$&*~]'));
      _hasMinLength = password.length >= 6;

      int strength = 0;
      if (_hasUppercase) strength++;
      if (_hasLowercase) strength++;
      if (_hasDigit) strength++;
      if (_hasSpecialChar) strength++;
      if (_hasMinLength) strength++;

      _passwordStrength = strength / 5;
      if (_passwordStrength <= 0.3) {
        _passwordStrengthLabel = 'Weak Password';
      } else if (_passwordStrength <= 0.7) {
        _passwordStrengthLabel = 'Fair Password';
      } else {
        _passwordStrengthLabel = 'Strong Password';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text(
                  'Are you sure you want to go back? Your entered data will be lost.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Yes, Go Back'),
                  ),
                ],
              ),
        );
        return shouldLeave ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sign Up'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 50,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Create an account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [
                      AutofillHints.newUsername,
                      AutofillHints.email,
                    ],
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email),
                      labelText: 'Email',
                      labelStyle: TextStyle(fontSize: 14),
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).nextFocus();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!EmailValidator.validate(value)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock),
                      labelText: 'Password',
                      labelStyle: const TextStyle(fontSize: 14),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    onChanged: _validatePasswordStrength,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (!_hasUppercase ||
                          !_hasLowercase ||
                          !_hasDigit ||
                          !_hasSpecialChar ||
                          !_hasMinLength) {
                        return 'Please meet all password requirements';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'Password strength: $_passwordStrengthLabel',
                        child: LinearProgressIndicator(
                          value: _passwordStrength,
                          backgroundColor: Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _passwordStrength <= 0.3
                                ? Colors.red
                                : _passwordStrength <= 0.7
                                ? Colors.orange
                                : Colors.green,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        label: _passwordStrengthLabel,
                        child: Text(
                          _passwordStrengthLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color:
                                _passwordStrength <= 0.3
                                    ? Colors.red
                                    : _passwordStrength <= 0.7
                                    ? Colors.orange
                                    : Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildChecklistItem(
                        'At least 6 characters',
                        _hasMinLength,
                      ),
                      _buildChecklistItem('1 uppercase letter', _hasUppercase),
                      _buildChecklistItem('1 lowercase letter', _hasLowercase),
                      _buildChecklistItem('1 number', _hasDigit),
                      _buildChecklistItem(
                        '1 special character (!@#\$&*~)',
                        _hasSpecialChar,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
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
                  const SizedBox(height: 5),
                  CheckboxListTile(
                    value: _acceptedTerms,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) {
                      setState(() {
                        _acceptedTerms = value ?? false;
                      });
                    },
                    title: GestureDetector(
                      onTap: () => _showTermsDialog(context),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 14),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms & Conditions',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    subtitle:
                        !_acceptedTerms
                            ? const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'You must accept the terms to continue',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            )
                            : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon:
                          _isLoading
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.person_add_alt_1_rounded),
                      onPressed: _isLoading ? null : _handleSignUp,
                      label: Text(_isLoading ? 'Signing up...' : 'Sign Up'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account?'),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Login',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
