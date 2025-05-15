import 'package:flutter/material.dart';

class AboutApp extends StatelessWidget {
  const AboutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About the App'),
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
                'PenCraft Pro',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'PenCraft Pro is a modern productivity app built for students, teachers, and creative professionals. It lets you take notes, draw, organize content, and sync seamlessly across devices.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Key Features:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• Smart note-taking with categories and labels\n'
                '• Drawing mode for sketches, diagrams, and handwriting\n'
                '• Cloud sync across devices\n'
                '• Secure login with email/password and Google Sign-In\n'
                '• Custom folders, archives, and recycle bin\n'
                '• Reminder functionality for important notes\n'
                '• Search and filter options for quick navigation\n'
                '• Email verification and password recovery support\n'
                '• Optimized for phones and tablets',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Version: 2.0.0',
                style: TextStyle(
                  fontSize: 16,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Developed by: PenCraft Pro Team',
                style: TextStyle(
                  fontSize: 16,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Having issues with your account or Want to delete it?',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Contact us at: pencraftpro1@gmail.com',
                style: TextStyle(
                  fontSize: 16,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
