import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:femwise/services/account_service.dart'; // Required for logout button
import 'guide_list_screen.dart'; // Ensure this path is correct
import 'package:femwise/screens/home_screen.dart'; // To navigate back to Home
import 'package:femwise/screens/daily_log_screen.dart'; // Import for DailyLogScreen
import 'package:femwise/packed_food/pack_foods_scan.dart'; // Import your food scanner screen
import 'package:femwise/food_options/food_options_screen.dart';

class SymptomSelectionScreen extends StatefulWidget {
  const SymptomSelectionScreen({super.key});

  @override
  State<SymptomSelectionScreen> createState() => _SymptomSelectionScreenState();
}

class _SymptomSelectionScreenState extends State<SymptomSelectionScreen> {
  void _onSymptomSelected(BuildContext context, String symptom) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuideListScreen(symptom: symptom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access the current theme's colorScheme for consistency
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Define your symptoms with associated icons and optional accent colors
    final List<Map<String, dynamic>> symptoms = [
      {
        'name': 'Stress',
        'icon': Icons.self_improvement, // General well-being/mindfulness
        'color': Colors.lightGreen.shade700,
      },
      {
        'name': 'Anxiety',
        'icon': Icons.sentiment_dissatisfied, // Reflects distress
        'color': Colors.blueAccent.shade700,
      },
      {
        'name': 'Insomnia',
        'icon': Icons.nightlight_round, // Sleep-related
        'color': Colors.indigo.shade700,
      },
      {
        'name': 'Fatigue', // Example of adding more symptoms
        'icon': Icons.hotel,
        'color': Colors.teal.shade700,
      },
      {
        'name': 'Cramps',
        'icon': Icons.sick,
        'color': Colors.pink.shade700,
      },
    ];

    return Scaffold(
      // Removed backgroundColor: Colors.transparent to allow the body's gradient to fill this area.
      appBar: AppBar(
        // Consistent AppBar styling from HomeScreen
        backgroundColor:
            Colors.deepPurple.shade400, // Matches DailyLogScreen's AppBar
        foregroundColor: Colors.white, // White text/icons for contrast
        elevation: 0, // No shadow for a flat look
        title: Text(
          "Choose Your Symptom",
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white, // White title for AppBar
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined, color: Colors.white),
            tooltip: 'Home',
            onPressed: () => Navigator.of(context).pushNamed('/home'),
          )
        ],
      ),
      body: Container(
        // Apply the same gradient background as HomeScreen and DailyLogScreen
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              20.0, 20.0, 20.0, 100.0), // Add bottom padding for FAB
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch, // Stretch cards to fill width
            children: symptoms.map((symptomData) {
              return Padding(
                padding: const EdgeInsets.only(
                    bottom: 20.0), // Spacing between cards
                child: _buildSymptomCard(
                  context,
                  symptomData['name'] as String,
                  symptomData['icon'] as IconData,
                  symptomData['color'] as Color,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFFFFFFFF), // Slightly transparent white
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.home,
                  color: Colors.grey.shade600,
                  size: 28), // Home icon is not selected
              onPressed: () {
                // Navigate back to the home screen. Using pop until first route if needed
                // Or if HomeScreen is always the root, use pushReplacement
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (Route<dynamic> route) => false, // Clears the stack
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.restaurant_menu,
                  color: Colors.grey.shade600,
                  size: 28), // Changed to a general food icon
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        const FoodOptionsScreen(), // Navigate to the new FoodOptionsScreen
                  ),
                );
              },
            ),
            // No Spacer needed as there's no FAB
            IconButton(
              // This screen's icon (Meditation/Symptom Selection) should be selected
              icon: Icon(Icons.self_improvement,
                  color: colorScheme.primary,
                  size: 28), // Highlighted in primary color
              onPressed: () {
                // Already on this screen, do nothing or provide feedback
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'You are already on the Symptom Selection screen!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Updated _buildSymptomCard for enhanced UI
  Widget _buildSymptomCard(BuildContext context, String symptomName,
      IconData icon, Color accentColor) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 8, // Increased elevation for more depth
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)), // More rounded corners
      clipBehavior:
          Clip.antiAlias, // Ensures internal content respects border radius
      child: InkWell(
        // Use InkWell for splash effect on tap
        onTap: () => _onSymptomSelected(context, symptomName.toLowerCase()),
        splashColor: accentColor.withValues(alpha: 0.2), // Light splash color
        highlightColor: accentColor.withValues(alpha: 0.05), // Subtle highlight
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              // Subtle gradient for card background for visual richness
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.white.withValues(
                    alpha: 0.9), // Keep it mostly white but add depth
                colorScheme.surface.withValues(
                    alpha: 0.7), // Use theme surface for consistency
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(20), // Match card shape
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(
                    alpha: 0.3), // Shadow matching accent color
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 25.0, horizontal: 20),
          child: Row(
            children: [
              Icon(
                icon,
                size: 40,
                color: accentColor, // Icon color based on symptom
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  symptomName,
                  style: GoogleFonts.poppins(
                    // Use Poppins for text consistency
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme
                        .onSurface, // Text color from theme for readability
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 24,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
