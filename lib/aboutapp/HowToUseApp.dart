import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HowToUseApp extends StatelessWidget {
  const HowToUseApp({super.key});

  // Function to launch URL
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to Use the App'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Getting Started with PenCraft Pro',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 24),
              _StepTitle('1. Sign In or Sign Up:'),
              _StepDetail(
                '• Use your email and password, or sign in with Google.',
              ),
              const SizedBox(height: 16),
              _StepTitle('2. Select Your Mode:'),
              _StepDetail(
                '• Choose between Notes and Drawing based on your task.',
              ),
              const SizedBox(height: 16),
              _StepTitle('3. Create and Manage Content:'),
              _StepDetail(
                '• Write notes or draw sketches.\n'
                '• Pin important items.\n'
                '• Archive or delete old content.',
              ),
              const SizedBox(height: 16),
              _StepTitle('4. Organize Efficiently:'),
              _StepDetail(
                '• Use folders, labels, and reminders to stay productive.',
              ),
              const SizedBox(height: 16),
              _StepTitle('5. Access Settings:'),
              _StepDetail(
                '• Manage your profile, change your password, or get help.',
              ),
              const SizedBox(height: 16),
              _StepTitle('6. Sync Across Devices:'),
              _StepDetail(
                '• Log in with the same account to keep your work updated anywhere.',
              ),
              const SizedBox(height: 16),
              _StepTitle('7. Customize Your Experience:'),
              _StepDetail(
                '• Choose a theme, manage font sizes, and set your default tools.',
              ),
              const SizedBox(height: 16),
              _StepTitle('8. Get Help and Updates:'),
              _StepDetail(
                '• Visit the Help section or check for the latest features in the About section.\n'
                '• Got questions or problems? Contact us at pencraftpro1@gmail.com or our official website ',
              ),
              GestureDetector(
                onTap: () => _launchUrl('https://tinyurl.com/pencraftpro'),
                child: Text(
                  'tinyurl.com/pencraftpro',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.tealAccent
                            : Colors.blue,
                    decoration: TextDecoration.underline,
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

class _StepTitle extends StatelessWidget {
  final String text;

  const _StepTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.tealAccent
                : Colors.red,
        fontWeight: FontWeight.bold,
        fontSize: 16,
        height: 1.4,
      ),
    );
  }
}

class _StepDetail extends StatelessWidget {
  final String text;

  const _StepDetail(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.6,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }
}
