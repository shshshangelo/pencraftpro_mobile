import 'dart:io';
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
import 'aboutapp/AboutTheApp.dart';
import 'aboutapp/FAQs.dart';
import 'aboutapp/HowToUseApp.dart';
import 'aboutapp/Team.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dashboard/DrawingDashboard.dart';
import 'drawing/DrawingPage.dart';
import 'drawing/SavedDrawingPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Failed to initialize Firebase: $e');
  }

  // Initialize timezone and set to Asia/Manila
  try {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    debugPrint('Timezone set to Asia/Manila');
  } catch (e) {
    debugPrint('Failed to initialize timezone: $e');
  }

  // Initialize notifications
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  try {
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    debugPrint('FlutterLocalNotifications initialized');
  } catch (e) {
    debugPrint('Failed to initialize notifications: $e');
  }

  // Check notification and battery optimization permissions (Android only)
  if (Platform.isAndroid) {
    final notificationPermission = await Permission.notification.status;
    debugPrint('Notification permission status: $notificationPermission');
    // Defer prompting to AddNotePage to avoid overwhelming users at startup

    if (Platform.version.contains('6.0') ||
        Platform.version.contains('7.0') ||
        Platform.version.contains('8.0') ||
        Platform.version.contains('9.0') ||
        Platform.version.contains('10.0') ||
        Platform.version.contains('11.0') ||
        Platform.version.contains('12.0') ||
        Platform.version.contains('13.0')) {
      final batteryOptimizationStatus =
          await Permission.ignoreBatteryOptimizations.status;
      debugPrint('Battery optimization status: $batteryOptimizationStatus');
      // Defer prompting to AddNotePage
    }
  }

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
      // Auto Light/Dark Mode setup here
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
      themeMode: ThemeMode.system,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape =
                  MediaQuery.of(context).orientation == Orientation.landscape;
              final imageSize = isLandscape ? 200.0 : 140.0;
              final containerWidth = isLandscape ? 400.0 : 300.0;
              final fontSize = isLandscape ? 40.0 : 30.0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: imageSize,
                    width: containerWidth,
                    child: Image.asset(
                      'assets/logo1.png',
                      fit: BoxFit.contain,
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
                      fontSize: fontSize,
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class RedirectPage extends StatefulWidget {
  const RedirectPage({super.key});

  @override
  State<RedirectPage> createState() => _RedirectPageState();
}

class _RedirectPageState extends State<RedirectPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () => handleRedirect());
  }

  Future<void> handleRedirect() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint("No user found, redirecting to /welcome");
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/welcome', (route) => false);
      return;
    }

    // Check email verification first
    await user.reload(); // Reload user to get latest verification status
    if (!mounted) return;

    if (!user.emailVerified &&
        !user.providerData.any((info) => info.providerId == 'google.com')) {
      debugPrint("Email not verified, redirecting to /verify");
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/verify', (route) => false);
      return;
    }

    bool isNameVerified = false;
    bool isRoleSelected = false;
    bool isIdVerified = false;
    bool isFirstTimeUser = true;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        isNameVerified = data['isNameVerified'] ?? false;
        isRoleSelected = data['isRoleSelected'] ?? false;
        isIdVerified = data['isIdVerified'] ?? false;
        isFirstTimeUser = data['isFirstTimeUser'] ?? true;
        debugPrint("Firestore flags loaded");
      } else {
        debugPrint("Firestore doc does not exist, fallback to prefs");
      }
    } catch (e) {
      debugPrint("Firestore error: $e — using SharedPreferences");
      final prefs = await SharedPreferences.getInstance();
      isNameVerified = prefs.getBool('isNameVerified') ?? false;
      isRoleSelected = prefs.getBool('isRoleSelected') ?? false;
      isIdVerified = prefs.getBool('isIdVerified') ?? false;
      isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;
    }

    if (!mounted) return;

    final isFullyVerified =
        isNameVerified && isRoleSelected && isIdVerified && !isFirstTimeUser;
    debugPrint("Verification Status: $isFullyVerified");

    if (isFullyVerified) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/select', (route) => false);
    } else {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/accountsettings', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
