import 'package:flutter/material.dart';

class Team extends StatelessWidget {
  const Team({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About the Team'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meet the Team Behind PenCraft Pro',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.tealAccent
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '"Without the heart, passion, and dedication of our team, PenCraft Pro would have never been brought to life."',
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey,
                ),
              ),
              const SizedBox(height: 30),
              const Member(name: 'Jenie A. Agbay', role: 'Leader'),
              const Member(
                name: 'Angelyn B. Brocal',
                role: 'Hardware Specialist',
              ),
              const Member(
                name: 'Trixie Velle P. Capuyan',
                role: 'Documentation Specialist',
              ),
              const Member(name: 'Albert H. Taghoy', role: 'Web Developer'),
              const Member(name: 'Cyrose Bernette Rosit', role: 'UI Designer'),
              const Member(
                name: 'Aira D. Malingin',
                role: 'Database Specialist',
              ),
              const Member(
                name: 'Michael Angelo E. Entera',
                role: 'Lead / Mobile Developer',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class Member extends StatelessWidget {
  final String name;
  final String role;

  const Member({super.key, required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 20,
              color:
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.tealAccent
                      : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• $role',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }
}
