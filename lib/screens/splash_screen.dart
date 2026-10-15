// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:femwise/widgets/pcos_logo.dart';
import 'dart:async'; // Required for Timer
import 'package:femwise/main.dart'; // Import your main.dart to access AuthWrapper

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Removed text-related state variables: _displayedText, _fullText, _currentIndex, _textAnimationTimer

  late AnimationController _logoAnimationController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;

  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseScaleAnimation;



  @override
  void initState() {
    super.initState();

    // Initialize logo entry animation controller
    _logoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
          milliseconds: 1200), // Duration for initial logo animation
    );

    // Define logo fade animation (from invisible to fully visible)
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.easeOut, // Smooth fade-in
      ),
    );

    // Define logo scale animation (from slightly smaller to normal size with a bounce)
    _logoScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.elasticOut, // Provides a nice bouncy effect
      ),
    );

    // Initialize pulse animation controller
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 1000), // Duration for one pulse cycle
    );

    // Define pulse scale animation (from normal size to slightly larger and back)
    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut, // Smooth in and out for pulsing
      ),
    );

    // Start initial logo animation
    _logoAnimationController.forward().then((_) {
      // After initial logo animation completes, start the pulsing animation
      _pulseAnimationController.repeat(
          reverse: true); // Repeats the animation back and forth

      // Navigate to the next screen after a total desired splash duration
      _navigateToNextScreen();
    });
  }

  void _navigateToNextScreen() {
    // Total duration for splash screen before navigating
    // This includes initial logo animation + some time for pulsing
    Future.delayed(const Duration(milliseconds: 3000), () {
      // 3 seconds total splash time
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (context) =>
                  const AuthWrapper()), // Navigate to AuthWrapper
        );
      }
    });
  }

  @override
  void dispose() {
    _logoAnimationController
        .dispose(); // Dispose the logo entry animation controller
    _pulseAnimationController
        .dispose(); // Dispose the logo pulse animation controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Background gradient consistent with your app's theme
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.deepPurple.shade50,
              Colors.purple.shade100,
              Colors.deepPurple.shade200,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated App Logo with initial entry and continuous pulse
              FadeTransition(
                opacity: _logoFadeAnimation, // Controls initial fade-in
                child: ScaleTransition(
                  scale: _logoScaleAnimation, // Controls initial scale-up
                  child: AnimatedBuilder(
                    // Use AnimatedBuilder for continuous pulsing
                    animation: _pulseScaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseScaleAnimation.value,
                        child: const PcosLogo(size: 200),
                      );
                    },
                  ),
                ),
              ),
              // Removed the animated text "Empowering Your Health"
            ],
          ),
        ),
      ),
    );
  }
}
