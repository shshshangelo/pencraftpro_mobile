import 'package:flutter/material.dart';

class FAQsPage extends StatelessWidget {
  const FAQsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {
        'question': 'Is PenCraft Pro free?',
        'answer': 'Yes, it is free with optional premium features.',
      },
      {
        'question': 'How do I save notes/drawings?',
        'answer':
            'Notes/Drawings need to be saved manually. Make sure to tap the save button after making changes to ensure your work is preserved.',
      },
      {
        'question': 'Can I use it offline?',
        'answer':
            'Yes, once you\'re logged in, you can use most features like taking note and drawings. However, logging in or signing up requires an internet connection for verification.',
      },
      {
        'question': 'Can I recover deleted notes?',
        'answer':
            'Yes. Deleted notes are stored in the Recycle Bin for 30 days.',
      },
      {
        'question': 'How do I change my password?',
        'answer':
            'Go to Account Settings and tap on "Change Password" under the email section.',
      },
      {
        'question': 'Is my data secure?',
        'answer':
            'Yes. We use Firebase Authentication and Cloud Firestore, which provide strong security measures.',
      },
      {
        'question': 'Can I use PenCraft Pro on multiple devices?',
        'answer':
            'Absolutely. As long as you log in with the same account, your notes sync across devices.',
      },
      {
        'question': 'Is my data backed up?',
        'answer':
            'Yes, your notes are securely stored in the cloud when you\'re online, so they\'re backed up automatically.',
      },
      {
        'question': 'What drawing tools are available?',
        'answer':
            'PenCraft Pro offers multiple brush types (normal, calligraphy, dotted, airbrush, marker) and image import capabilities. You can also use the color picker and eyedropper tool for precise color selection.',
      },
      {
        'question': 'Can I undo/redo my drawing actions?',
        'answer':
            'Yes, you can use the undo/redo functionality to revert or reapply your drawing actions.',
      },
      {
        'question': 'Can I import images into my drawings?',
        'answer':
            'Yes, you can import images and manipulate them within your drawings. You can resize, move, and adjust the images as needed.',
      },
      {
        'question': 'Can I save my drawing in JPEG?',
        'answer': 'Yes, you can as long as you have done the drawing.',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text('FAQs'),
        actions: [],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        itemCount: faqs.length + 1, // +1 for contact info
        itemBuilder: (context, index) {
          if (index < faqs.length) {
            final faq = faqs[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  faq['question']!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.tealAccent
                            : Colors.red,
                    height: 1.4,
                  ),
                ),
                children: [
                  Text(
                    faq['answer']!,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [],
              ),
            );
          }
        },
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}
