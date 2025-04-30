import 'package:flutter/material.dart';
import '../drawing/DrawingPage.dart'; // Import the New Drawing page
import '../drawing/SavedDrawingPage.dart'; // Import the Saved Drawings page

class DrawingDashboard extends StatelessWidget {
  const DrawingDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center vertically
            crossAxisAlignment:
                CrossAxisAlignment.center, // Center horizontally
            children: [
              Image.asset(
                'assets/aclc.png',
                width: 250, // Adjust width as needed
                height: 200, // Adjust height as needed
                fit: BoxFit.contain, // Ensure the logo scales properly
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to Your Drawing Dashboard',
                textAlign: TextAlign.center, // Ensure text is centered
                style: TextStyle(
                  fontFamily: 'Satisfy',
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap:
                    true, // Prevent GridView from expanding unnecessarily
                physics:
                    const NeverScrollableScrollPhysics(), // Disable scrolling
                children: [
                  _buildDashboardCard(
                    context,
                    icon: Icons.draw_rounded,
                    title: 'New Drawing',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DrawingCanvasPage(),
                        ),
                      );
                    },
                  ),
                  _buildDashboardCard(
                    context,
                    icon: Icons.folder_open,
                    title: 'Saved Drawings',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SavedDrawingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
