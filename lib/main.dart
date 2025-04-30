import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth/Login.dart';
import 'auth/SignUp.dart';
import 'auth/ForgotPassword.dart';
import 'SelectionAction.dart';
import 'auth/ChangePasswordPage.dart';
import 'dashboard/NotesDashboard.dart';
import 'notes/AddNotePage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/AccountSettings.dart';
import 'pages/Archive.dart';
import 'pages/RecycleBin.dart';
import 'pages/Folders.dart';
import 'pages/Labels.dart';
import 'pages/Reminders.dart';
import 'aboutapp/AboutApp.dart';
import 'aboutapp/FAQsPage.dart';
import 'aboutapp/HowToUseApp.dart';
import 'aboutapp/Team.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'dashboard/DrawingDashboard.dart';
import 'drawing/DrawingPage.dart';
import 'drawing/SavedDrawingPage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  tz.initializeTimeZones();

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'PenCraft Pro',
      debugShowCheckedModeBanner: false,
      // 🔥 Auto Light/Dark Mode setup here
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.blue,
          secondary: Colors.red,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
          bodyLarge: TextStyle(fontSize: 25, color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSwatch(
          brightness: Brightness.dark,
          primarySwatch: Colors.blueGrey,
        ).copyWith(secondary: Colors.tealAccent),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.tealAccent,
          ),
          bodyLarge: TextStyle(fontSize: 25, color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
      themeMode: ThemeMode.system, // 🔥 Sundan system ng device
      initialRoute: '/',
      routes: {
        '/': (context) => const RedirectPage(),
        '/welcome': (context) => const MyHomePage(title: 'PenCraft Pro'),
        '/login': (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          final showWelcomeBack = args?['showWelcomeBack'] ?? false;
          return Login(showWelcomeBack: showWelcomeBack);
        },
        '/signup': (context) => const SignUp(),
        '/forgotpassword': (context) => const ForgotPassword(),
        '/select': (context) => const SelectionAction(),
        '/notes': (context) => const NotesDashboard(),
        '/addNote': (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;

          return AddNotePage(
            noteId: args?['noteId'] as String?,
            title: args?['title'] as String?,
            contentJson:
                (args?['contentJson'] as List?)?.cast<Map<String, dynamic>>(),
            isPinned: args?['isPinned'] as bool? ?? false,
            reminder: args?['reminder'] as DateTime?,
            imagePaths: (args?['imagePaths'] as List?)?.cast<String>(),
            voiceNote: args?['voiceNote'] as String?,
            labels: args?['labels'] as List<String>?,
            isArchived: args?['isArchived'] as bool? ?? false,
            fontFamily: args?['fontFamily'] as String?,
            folderId: args?['folderId'] as String?,
            folderColor: args?['folderColor'] as int?,
            onSave: ({
              String? id,
              required String title,
              required List<Map<String, dynamic>> contentJson,
              required bool isPinned,
              required bool isDeleted,
              DateTime? reminder,
              List<String>? imagePaths,
              String? voiceNote,
              List<String>? labels,
              bool? isArchived,
              String? fontFamily,
              String? folderId,
              int? folderColor,
              List<String>? collaboratorEmails,
            }) {
              Navigator.of(context).pop({
                'id': id,
                'title': title,
                'contentJson': contentJson,
                'isPinned': isPinned,
                'isDeleted': isDeleted,
                'reminder': reminder,
                'imagePaths': imagePaths,
                'voiceNote': voiceNote,
                'labels': labels,
                'isArchived': isArchived,
                'fontFamily': fontFamily,
                'folderId': folderId,
                'folderColor': folderColor,
                'collaboratorEmails': collaboratorEmails,
              });
            },
            onDelete: (String id) {
              Navigator.of(context).pop({'id': id, 'delete': true});
            },
          );
        },
        '/accountsettings': (context) => const AccountSettings(),
        '/archive': (context) => const Archive(),
        '/deleted': (context) => const RecycleBin(),
        '/folders': (context) => const Folders(),
        '/labels': (context) => const Labels(),
        '/reminders': (context) => const Reminders(),
        '/about': (context) => const AboutApp(),
        '/howtouse': (context) => const HowToUseApp(),
        '/faqs': (context) => const FAQsPage(),
        '/team': (context) => const Team(),
        '/changepassword': (context) => const ChangePasswordPage(),
        '/drawing': (context) => const DrawingDashboard(),
        '/newdrawingpage': (context) => DrawingCanvasPage(),
        '/saveddrawingpage': (context) => SavedDrawingsPage(),
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 140,
                width: 300,
                child: Image.asset(
                  'assets/logo1.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.broken_image,
                      size: 100,
                      color: Colors.grey,
                    );
                  },
                ),
              ),
              const SizedBox(height: 15),
              Text(
                '"Write It. Draw It. Own It."',
                style: GoogleFonts.dancingScript(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/login');
                },
                child: const Text('Get Started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RedirectPage extends StatelessWidget {
  const RedirectPage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/welcome', (route) => false);
      } else {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data()!;
          final isNameVerified = data['isNameVerified'] ?? false;
          final isRoleSelected = data['isRoleSelected'] ?? false;
          final isIdVerified = data['isIdVerified'] ?? false;
          final isFirstTimeUser = data['isFirstTimeUser'] ?? true;

          if (isNameVerified &&
              isRoleSelected &&
              isIdVerified &&
              !isFirstTimeUser) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/select', (route) => false);
          } else {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/accountsettings', (route) => false);
          }
        } else {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/accountsettings', (route) => false);
        }
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
