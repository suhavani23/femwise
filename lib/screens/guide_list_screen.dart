import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // Import for custom fonts
import 'package:femwise/services/account_service.dart'; // Required for logout button
import 'guide_run_screen.dart';
import 'package:femwise/screens/home_screen.dart'; // To navigate back to Home
import 'package:femwise/screens/daily_log_screen.dart'; // Import for DailyLogScreen
import 'package:femwise/screens/symptom_selection_screen.dart'; // To navigate back to Symptom Selection
import 'package:femwise/packed_food/pack_foods_scan.dart'; // Import your food scanner screen
import 'package:femwise/food_options/food_options_screen.dart';

class GuideListScreen extends StatefulWidget {
  final String symptom;

  const GuideListScreen({super.key, required this.symptom});

  @override
  State<GuideListScreen> createState() => _GuideListScreenState();
}

class _GuideListScreenState extends State<GuideListScreen> {
  List<dynamic> guides = [];
  bool _isLoading = true; // Added loading state

  // Restructured to a Map: Symptom Name -> List of Image Asset Paths for that Symptom
  final Map<String, List<String>> _symptomGuideImages = {
    'stress': [
      'assets/lists/stress_1.jpg',
      'assets/lists/stress_2.jpg',
    ],
    'anxiety': [
      'assets/lists/anxiety_1.jpg',
      'assets/lists/anxiety_2.jpg',
    ],
    'insomnia': [
      'assets/lists/insomnia_1.jpg',
      'assets/lists/insomnia_2.jpeg',
    ],
    // Add other symptoms here with their dedicated image paths
    // e.g.,
    // 'fatigue': [
    //   'assets/lists/fatigue_1.jpg',
    //   'assets/lists/fatigue_2.jpg',
    // ],
    // 'cramps': [
    //   'assets/lists/cramps_1.jpg',
    //   'assets/lists/cramps_2.jpg',
    // ],
  };

  @override
  void initState() {
    super.initState();
    loadGuides();
  }

  Future<void> loadGuides() async {
    setState(() {
      _isLoading = true; // Set loading to true when starting to load guides
    });
    // Declare fileName here to make it accessible in the catch block
    String fileName = '';
    try {
      fileName = widget.symptom.toLowerCase() + '.json'; // Assign value here
      final String data = await rootBundle.loadString('assets/jsons/$fileName');
      final List<dynamic> jsonResult = json.decode(data);
      setState(() {
        guides = jsonResult;
      });
    } catch (e) {
      print('Error loading guide for ${widget.symptom}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load guides for ${widget.symptom}. Please check assets/jsons/$fileName.')),
        );
      }
      setState(() {
        guides = []; // Clear guides on error
      });
    } finally {
      setState(() {
        _isLoading = false; // Set loading to false once loading is complete
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Get the list of images for the current symptom
    final List<String> currentSymptomImages = _symptomGuideImages[widget.symptom.toLowerCase()] ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.shade400,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${widget.symptom} Guides',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white, size: 26),
            onPressed: () async {
              try {
                await AccountService.instance.signOut();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Unable to sign out. Check your connection: $e')),
                  );
                }
                return;
              }
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
          ),
        ],
      ),
      body: Container(
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
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
            : guides.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sentiment_dissatisfied, size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text(
                'No guides available for ${widget.symptom} yet.',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
            : ListView.builder(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0), // Padding for FAB and bottom nav
          itemCount: guides.length,
          itemBuilder: (context, index) {
            final guide = guides[index];
            // Get image path from the symptom-specific list.
            // If currentSymptomImages is empty, or index is out of bounds, use a default fallback.
            final String imagePath = currentSymptomImages.isNotEmpty && index < currentSymptomImages.length
                ? currentSymptomImages[index]
                : 'assets/lists/default_fallback.jpg'; // Make sure you have a default_fallback.jpg!

            return Card(
              margin: const EdgeInsets.only(bottom: 15.0),
              elevation: 5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GuideRunScreen(guide: guide),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Column( // Use Column to stack image and text content
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image at the top of the card
                    ClipRRect( // Clip the image to match card's top border radius
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: AspectRatio( // <--- Adjusted AspectRatio
                        aspectRatio: 2.0, // This is the height control. Adjust if needed for a taller/shorter box
                        child: Image.asset( // Now using dynamic asset path
                          imagePath, // This will change for each guide based on its index
                          fit: BoxFit.cover,
                          width: double.infinity, // Occupy full width of the card
                          // Error builder for fallback in case image fails to load (less common for assets)
                          errorBuilder: (context, error, stackTrace) => Container(
                            // This container will automatically take the size dictated by AspectRatio
                            color: Colors.grey.shade200,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 40),
                                  const SizedBox(height: 5),
                                  Text('Image Missing', style: GoogleFonts.montserrat(color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0), // Padding for the text content
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guide['title'] ?? 'No Title',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            guide['goal'] ?? 'No Goal',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Icon(
                              Icons.arrow_forward_ios,
                              color: colorScheme.primary.withOpacity(0.7),
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFFFFFFFF), // Changed to white
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.home, color: Colors.grey.shade600, size: 28), // Home icon unselected
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                      (Route<dynamic> route) => false,
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.restaurant_menu, color: Colors.grey.shade600, size: 28), // Changed to a general food icon
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const FoodOptionsScreen(), // Navigate to the new FoodOptionsScreen
                  ),
                );
              },
            ),
            // No Spacer needed as there's no FAB
            IconButton(
              icon: Icon(Icons.self_improvement, color: colorScheme.primary, size: 28), // Meditation/Symptom icon selected
              onPressed: () {
                // Pop all routes until SymptomSelectionScreen, or the very first route
                Navigator.of(context).popUntil((route) {
                  return route.isFirst || (route.settings.name == '/symptomSelection');
                });
                // After popping, if the current top route is not the SymptomSelectionScreen,
                // then push SymptomSelectionScreen as a replacement.
                // We must use `ModalRoute.of(context)` to get the settings of the current route.
                if (ModalRoute.of(context)?.settings.name != '/symptomSelection') {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const SymptomSelectionScreen(),
                      settings: const RouteSettings(name: '/symptomSelection'), // Ensure it has a name
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
