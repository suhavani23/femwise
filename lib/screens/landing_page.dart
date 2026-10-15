import 'package:flutter/material.dart';
import 'package:femwise/screens/home_screen.dart'; // Import the new Home Screen

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // We navigate immediately to HomeScreen after the LandingPage is built.
    // This is a common pattern for initial redirection after authentication.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    });

    // You can return an empty Scaffold or a loading indicator here
    // while the navigation happens.
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(), // Show a loading indicator briefly
      ),
    );
  }
}
