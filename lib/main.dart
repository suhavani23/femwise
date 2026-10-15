import 'package:flutter/material.dart';
import 'services/account_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FemWise',
        theme: ThemeData(
          primarySwatch: Colors.pink,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const AccountStartup(),
        routes: {'/login': (_) => const LoginScreen()},
        debugShowCheckedModeBanner: false,
      );
}

class AccountStartup extends StatefulWidget {
  const AccountStartup({super.key});
  @override
  State<AccountStartup> createState() => _AccountStartupState();
}

class _AccountStartupState extends State<AccountStartup> {
  late Future<void> _initialization;
  @override
  void initState() {
    super.initState();
    _initialization = AccountService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(body: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to restore your session. Check your connection.'),
                TextButton(onPressed: () => setState(() {
                  _initialization = AccountService.instance.initialize();
                }), child: const Text('Retry')),
              ],
            )));
          }
          return const SplashScreen();
        },
      );
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AccountUser?>(
        stream: AccountService.instance.authStateChanges(),
        initialData: AccountService.instance.currentUser,
        builder: (context, snapshot) {
          if (snapshot.data == null) return const LoginScreen();
          return FutureBuilder<Map<String, dynamic>>(
            future: AccountService.instance.getProfile(),
            builder: (context, profile) {
              if (profile.hasError) {
                return const Scaffold(body: Center(
                    child: Text('Unable to load your profile. Please reopen the app to retry.')));
              }
              if (!profile.hasData) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              return profile.data!['onboardingComplete'] == true
                  ? const HomeScreen() : const OnboardingScreen();
            },
          );
        },
      );
