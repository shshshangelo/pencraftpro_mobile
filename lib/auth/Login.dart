// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SignUp.dart';
import 'ForgotPassword.dart';

class Login extends StatefulWidget {
  final bool showWelcomeBack;

  const Login({super.key, this.showWelcomeBack = false});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isFirstLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
    _checkCurrentUser();
    _isFirstLogin = !widget.showWelcomeBack;
  }

  Future<void> _checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && mounted) {
      await user.reload();
      if (user.emailVerified) {
        Navigator.pushNamedAndRemoveUntil(context, '/select', (route) => false);
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/verify', (route) => false);
      }
    }
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('email') ?? '';
    final rememberMe = prefs.getBool('rememberMe') ?? false;
    setState(() {
      _emailController.text = savedEmail;
      _rememberMe = rememberMe;
      _isFirstLogin = savedEmail.isEmpty;
    });
  }

  Future<void> _saveEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('email', _emailController.text.trim());
      await prefs.setBool('rememberMe', true);
    } else {
      await prefs.remove('email');
      await prefs.setBool('rememberMe', false);
    }
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await _saveEmail();
        final userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
        if (!mounted) return;
        final user = userCredential.user;
        if (user != null) {
          await user.reload();
          if (user.emailVerified) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/select',
              (route) => false,
            );
          } else {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/verify',
              (route) => false,
            );
          }
        }
      } catch (e) {
        String errorMessage = 'Login failed. Please try again.';
        if (e is FirebaseAuthException) {
          switch (e.code) {
            case 'user-not-found':
              errorMessage = 'No user found with this email.';
              break;
            case 'wrong-password':
              errorMessage = 'Incorrect password.';
              break;
            case 'invalid-email':
              errorMessage = 'Invalid email format.';
              break;
          }
        }
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
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (user != null) {
        await user.reload();
        final prefs = await SharedPreferences.getInstance();
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

        if (!isNewUser) {
          final userDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();

          if (userDoc.exists) {
            final data = userDoc.data()!;
            await prefs.setBool(
              'isNameVerified',
              data['isNameVerified'] ?? false,
            );
            await prefs.setBool(
              'isRoleSelected',
              data['isRoleSelected'] ?? false,
            );
            await prefs.setBool('isIdVerified', data['isIdVerified'] ?? false);
            await prefs.setBool(
              'isFirstTimeUser',
              data['isFirstTimeUser'] ?? false,
            );
            await prefs.setString('fullName', data['fullName'] ?? '');
            await prefs.setString('selectedRole', data['role'] ?? 'Student');
            await prefs.setString('studentId', data['idNumber'] ?? '');
            await prefs.setString('teacherId', data['idNumber'] ?? '');
            await prefs.setString(
              'profileInitials',
              data['profileInitials'] ?? _getInitials(data['fullName'] ?? ''),
            );
          }
        }

        if (user.emailVerified) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/select',
            (route) => false,
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/verify',
            (route) => false,
          );
        }
      }
    } catch (e) {
      String errorMessage = 'Google Sign-In failed.';
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'account-exists-with-different-credential':
            errorMessage = 'Account exists with different sign-in method.';
            break;
          case 'invalid-credential':
            errorMessage = 'Invalid credentials.';
            break;
        }
      }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0].toUpperCase()}${parts.last[0].toUpperCase()}';
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Login'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/welcome',
                (route) => false,
              );
            },
          ),
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
                    Icons.lock_open_rounded,
                    size: 50,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isFirstLogin ? 'Login' : 'Welcome back,',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildEmailField(),
                  const SizedBox(height: 20),
                  _buildPasswordField(),
                  const SizedBox(height: 10),
                  _buildRememberMeRow(),
                  const SizedBox(height: 20),
                  _buildLoginButton(),
                  const SizedBox(height: 20),
                  _buildDivider(),
                  const SizedBox(height: 20),
                  _buildGoogleSignInButton(),
                  const SizedBox(height: 30),
                  _buildSignUpRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() => TextFormField(
    controller: _emailController,
    focusNode: _emailFocusNode,
    autofillHints: const [AutofillHints.username, AutofillHints.email],
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.email_outlined),
      labelText: 'Email',
      labelStyle: Theme.of(context).textTheme.bodyMedium,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      if (value == null || value.isEmpty) return 'Please enter your email';
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
      if (!emailRegex.hasMatch(value)) return 'Please enter a valid email';
      return null;
    },
  );

  Widget _buildPasswordField() => TextFormField(
    controller: _passwordController,
    obscureText: _obscurePassword,
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.password],
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.lock_outline),
      labelText: 'Password',
      labelStyle: Theme.of(context).textTheme.bodyMedium,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    ),
    validator: (value) {
      if (value == null || value.isEmpty) return 'Please enter your password';
      if (value.length < 6) return 'Password must be at least 6 characters';
      return null;
    },
  );

  Widget _buildRememberMeRow() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Checkbox(
            value: _rememberMe,
            onChanged: (value) {
              setState(() => _rememberMe = value ?? false);
              _saveEmail();
            },
          ),
          Text('Remember me', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      TextButton(
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ForgotPassword()),
            ),
        child: Text(
          'Forgot Password?',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.blue),
        ),
      ),
    ],
  );

  Widget _buildLoginButton() => SizedBox(
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
              : const Icon(Icons.login),
      onPressed: _isLoading ? null : _handleLogin,
      label: Text(_isLoading ? 'Logging in...' : 'Login'),
    ),
  );

  Widget _buildDivider() => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Text('or', style: TextStyle(color: Colors.grey[600])),
      ),
      const Expanded(child: Divider()),
    ],
  );

  Widget _buildGoogleSignInButton() => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      icon:
          _isGoogleLoading
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.g_mobiledata, size: 28),
      label: Text(_isGoogleLoading ? 'Signing in...' : 'Continue with Google'),
      onPressed: _isGoogleLoading ? null : _signInWithGoogle,
    ),
  );

  Widget _buildSignUpRow() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        "Don't have an account?",
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      TextButton(
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SignUp()),
            ),
        child: Text(
          'Sign Up',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    ],
  );
}
