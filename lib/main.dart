import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shop/route/router.dart' as router;
import 'package:shop/route/route_constants.dart';
import 'package:shop/app_config.dart';
import 'package:shop/screens/splash/splash_screen.dart';
import 'package:shop/theme/app_theme.dart';
import 'package:shop/theme/theme_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final isCashier = kAppRole.toLowerCase() == 'cashier';
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: isCashier ? 'Supremo Barbers (Cashier)' : 'Supremo Barbers',
            theme: AppTheme.lightTheme(context),
            darkTheme: AppTheme.darkTheme(context),
            themeMode: themeProvider.themeMode,
            onGenerateRoute: router.generateRoute,
            // Route using a gate so signed-in users persist across restarts
            home: _RootGate(isCashier: isCashier),
          );
        },
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  final bool isCashier;
  const _RootGate({required this.isCashier});

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    if (!mounted) return;
    if (!widget.isCashier) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
      return;
    }

    // Cashier flavor: honor persisted auth session
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacementNamed(context, LoginEmployeeScreenRoute);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? {};
      final role = (data['role'] ?? '').toString();
      String? branchId = (data['branchId'] ?? '').toString();
      if (branchId.isEmpty) branchId = kHardwiredBranchId;

      if (role == 'cashier' || role == 'admin') {
        Navigator.pushReplacementNamed(
          context,
          cashierQueueScreenRoute,
          arguments: branchId,
        );
        return;
      }
    } catch (_) {}

    // Fallback: go to staff login
    Navigator.pushReplacementNamed(context, LoginEmployeeScreenRoute);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
