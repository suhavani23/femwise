import 'package:flutter/material.dart';
import 'password_recovery_screen.dart';
import 'package:femwise/widgets/pcos_logo.dart';
import 'package:femwise/services/account_service.dart';
import 'package:femwise/services/api_config.dart';
import 'package:femwise/screens/home_screen.dart';
import 'package:femwise/screens/onboarding_screen.dart';
import 'package:femwise/screens/sign_up_screen.dart';
import 'package:google_fonts/google_fonts.dart'; // Import google_fonts

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _showServerConfigDialog() async {
    final controller = TextEditingController(text: ApiConfig.accounts);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the address of your PC running the backend:\n(e.g., http://10.60.73.214:8002)',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'http://10.60.73.214:8002',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ApiConfig.setAccountsUrl(controller.text.trim());
                if (mounted) {
                  setState(() {
                    _errorMessage = null;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Server set to: ${ApiConfig.accounts}')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }


  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Helper function for navigation after successful auth ---
  Future<void> _handlePostAuthNavigation(AccountUser user) async {
    final userData = await AccountService.instance.getProfile();
    final bool onboardingComplete = userData['onboardingComplete'] == true;

    print(
        'LoginScreen: User authenticated: ${user.email}, Onboarding complete: $onboardingComplete');

    if (mounted) {
      if (onboardingComplete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
          (route) => false,
        );
      }
    }
  }

  // --- Sign In Function ---
  Future<void> _signInUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_formKey.currentState!.validate()) {
      try {
        final user = await AccountService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (mounted) {
          await _handlePostAuthNavigation(user);
        }
      } on AccountException catch (e) {
        if (mounted)
          setState(() {
            _errorMessage = e.message;
          });
      } catch (e) {
        setState(() {
          _errorMessage = 'An unexpected error occurred: $e';
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar:
          true, // Allows body to go behind transparent app bar
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Transparent app bar
        elevation: 0, // No shadow
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_rounded, color: Colors.deepPurple),
            tooltip: 'Server Settings',
            onPressed: _showServerConfigDialog,
          ),
        ],
      ),
      body: Container(
        // Background gradient from home_screen.dart
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 12, // Increased elevation for a more prominent card
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25)),
              color: Colors.white
                  .withValues(alpha: 0.95), // Slightly opaque white card
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 30.0, vertical: 40.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min, // Make column take minimum space
                    children: <Widget>[
                      // App Logo
                      const PcosLogo(),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome Back!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          // Attractive style for greeting
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors
                              .deepPurple.shade700, // Darker purple for heading
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in to continue your journey.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.montserrat(
                            fontSize: 16, color: Colors.grey.shade800),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: GoogleFonts.montserrat(
                              color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide.none, // Remove default border
                          ),
                          filled: true,
                          fillColor: Colors.deepPurple.shade50
                              .withValues(alpha: 0.5), // Light purple fill
                          prefixIcon: Icon(Icons.email,
                              color: Colors.deepPurple.shade400),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.deepPurple.shade400, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.deepPurple.shade200, width: 1),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        style: GoogleFonts.montserrat(
                            fontSize: 16, color: Colors.grey.shade800),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: GoogleFonts.montserrat(
                              color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor:
                              Colors.deepPurple.shade50.withValues(alpha: 0.5),
                          prefixIcon: Icon(Icons.lock,
                              color: Colors.deepPurple.shade400),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.deepPurple.shade400, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.deepPurple.shade200, width: 1),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters long';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),

                      // Error Message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Column(
                            children: [
                              Text(
                                _errorMessage!,
                                style: GoogleFonts.montserrat(
                                    color: Colors.red.shade700,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                                textAlign: TextAlign.center,
                              ),
                              if (_errorMessage!.contains('SocketException') ||
                                  _errorMessage!.contains('Connection timed out') ||
                                  _errorMessage!.contains('10.0.2.2'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.settings_ethernet,
                                        size: 18),
                                    label: const Text('Change Server IP'),
                                    onPressed: _showServerConfigDialog,
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Login Button
                      Container(
                        width: double.infinity, // Make button full width
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              15), // Rounded corners for button
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFD3A4F4),
                              Color(0xFF8A2BE2)
                            ], // Lighter to Darker Purple
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8A2BE2)
                                  .withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signInUser,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            backgroundColor: Colors
                                .transparent, // Make transparent to show gradient
                            shadowColor: Colors
                                .transparent, // No shadow from button itself
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : Text(
                                  'Log In',
                                  style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const PasswordRecoveryScreen())),
                        child: const Text('Forgot password?'),
                      ),
                      // Sign Up Button (centered)
                      Center(
                        // Centered as requested
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const SignUpScreen()),
                                  );
                                },
                          child: Text(
                            'Don\'t have an account? Sign Up',
                            style: GoogleFonts.montserrat(
                              color: Colors.deepPurple
                                  .shade700, // Darker purple for text button
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
