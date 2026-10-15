import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:femwise/services/account_service.dart';
import 'package:intl/intl.dart';
import 'dart:math'; // Import for min/max functions
import 'package:femwise/screens/daily_log_screen.dart';
import 'package:google_fonts/google_fonts.dart'; // Import google_fonts
import 'package:femwise/screens/symptom_selection_screen.dart'; // Adjust path as needed for your symptom selection screen
import 'package:femwise/packed_food/pack_foods_scan.dart'; // Import your food scanner screen
import 'package:femwise/food_options/food_options_screen.dart';

// Enum must be at the top-level (outside the class)
enum CalendarMarkerType {
  currentPeriod,
  predictedPeriod,
  predictedOvulation,
  predictedFertile,
  // Removed 'selectedDay' from enum
  today,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focusedDay = DateTime.now();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  // Data fetched from the account API
  DateTime? _lastPeriodStartDate;
  int? _typicalCycleLength; // This is crucial for future predictions
  int? _averagePeriodDuration; // Used for marking current period days

  // Calculated prediction dates
  DateTime? _predictedNextPeriodStart;
  DateTime? _predictedOvulationDay;
  List<DateTime> _predictedFertileWindow = [];

  // Define shades for current period days: darker to lighter reds
  final List<Color> _periodShades = [
    const Color(0xFFC62828), // Darkest Red
    const Color(0xFFD32F2F),
    const Color(0xFFE53935),
    const Color(0xFFEF5350),
    const Color(0xFFE57373), // Light Red (for current period)
  ];

  // Define custom colors for other markers (text colors for ovulation/fertile, circles for today/selected)
  final Color _predictedPeriodColor =
      const Color(0xFFAD1457); // Dark Pink (Changed for 'Next Period')
  final Color _predictedOvulationTextColor =
      const Color(0xFFF9A825); // Amber A700 (text only on calendar)
  final Color _predictedFertileTextColor =
      const Color(0xFF4CAF50); // Green 500 (text only on calendar)

  // Current Day (Today) color changed to purple
  final Color _todayBorderColor =
      const Color(0xFF673AB7); // Deep Purple (border)
  final Color _todayFillColor =
      const Color(0xFFD1C4E9); // Light Purple 100 (fill for Today)

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndMakeInitialPrediction();
  }

  // Fetches user profile data and then triggers prediction calculation
  Future<void> _fetchUserDataAndMakeInitialPrediction() async {
    final user = AccountService.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final userDoc = await AccountService.instance.getProfile();

      if (userDoc.isNotEmpty) {
        _userData = userDoc;

        dynamic lastPeriodStartDateData = _userData!['lastPeriodStartDate'];
        if (lastPeriodStartDateData is String) {
          try {
            _lastPeriodStartDate =
                DateFormat('yyyy-MM-dd').parse(lastPeriodStartDateData);
          } catch (e) {
            print('Error parsing lastPeriodStartDate string: $e');
            _lastPeriodStartDate = null;
          }
        } else {
          _lastPeriodStartDate = null;
        }

        _typicalCycleLength = _userData!['typicalCycleLength'] as int?;
        _averagePeriodDuration = _userData!['averagePeriodDuration'] as int?;

        _makeFormulaBasedPrediction();
      } else {
        print('User data not found for ${user.uid}');
      }
    } catch (e) {
      print('Error fetching user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load user data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Calculates future predictions based on fetched user data
  void _makeFormulaBasedPrediction() {
    if (_lastPeriodStartDate != null &&
        _typicalCycleLength != null &&
        _typicalCycleLength! > 0) {
      // Predicted Next Period Start: Add typical cycle length to last period start
      _predictedNextPeriodStart =
          _lastPeriodStartDate!.add(Duration(days: _typicalCycleLength!));

      // Ovulation is typically around 14 days before the *next* period
      _predictedOvulationDay =
          _predictedNextPeriodStart!.subtract(const Duration(days: 14));

      _predictedFertileWindow.clear();
      // Fertile window is typically 5 days before ovulation, ovulation day, and 1 day after ovulation
      if (_predictedOvulationDay != null) {
        for (int i = -5; i <= 1; i++) {
          _predictedFertileWindow
              .add(_predictedOvulationDay!.add(Duration(days: i)));
        }
      }
    } else {
      // Clear predictions if data is insufficient
      _predictedNextPeriodStart = null;
      _predictedOvulationDay = null;
      _predictedFertileWindow.clear();
    }
  }

  // Determines what markers/visuals apply to a given day on the calendar
  List<CalendarMarkerType> _getMarkerTypesForDay(DateTime day) {
    List<CalendarMarkerType> types = [];

    // Check for current period days (based on lastPeriodStartDate and averagePeriodDuration)
    if (_lastPeriodStartDate != null && _averagePeriodDuration != null) {
      for (int i = 0; i < _averagePeriodDuration!; i++) {
        DateTime periodDay = _lastPeriodStartDate!.add(Duration(days: i));
        if (isSameDay(periodDay, day)) {
          types.add(CalendarMarkerType.currentPeriod);
          break; // Only add once per day
        }
      }
    }

    // Check for predicted period
    if (_predictedNextPeriodStart != null &&
        isSameDay(_predictedNextPeriodStart!, day)) {
      types.add(CalendarMarkerType.predictedPeriod);
    }

    // Check for predicted ovulation
    if (_predictedOvulationDay != null &&
        isSameDay(_predictedOvulationDay!, day)) {
      types.add(CalendarMarkerType.predictedOvulation);
    }

    // Check for predicted fertile window
    if (_predictedFertileWindow.any((fDay) => isSameDay(fDay, day))) {
      types.add(CalendarMarkerType.predictedFertile);
    }

    return types;
  }

  // New: Method to fetch daily log for a specific date
  Future<Map<String, dynamic>?> _fetchDailyLogForDate(DateTime date) async {
    final user = AccountService.instance.currentUser;
    if (user == null) {
      return null;
    }

    try {
      return await AccountService.instance
          .getDailyLog(DateFormat('yyyy-MM-dd').format(date));
    } catch (e) {
      print('Error fetching daily log for date $date: $e');
      return null;
    }
  }

  // Function to show daily log details in a dialog
  void _showDailyLogDetails(
      BuildContext context, DateTime date, Map<String, dynamic>? logData) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: EdgeInsets.zero, // Remove default title padding
          contentPadding: const EdgeInsets.fromLTRB(
              24, 0, 24, 24), // Adjust content padding
          title: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: colorScheme.primary, // Primary color for the header
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Text(
              'Daily Log for\n${DateFormat('EEEE, MMM dd, yyyy').format(date)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color:
                    colorScheme.onPrimary, // White text on primary background
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: logData == null || logData.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sentiment_dissatisfied,
                            size: 50, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'No log entry for this date.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      _buildLogDetailCard(
                        context,
                        title: 'General Health',
                        details: [
                          _buildDetailRow(
                            context,
                            icon: Icons.mood_outlined,
                            label: 'Mood:',
                            value: logData['mood'] ?? 'N/A',
                            valueColor: Colors.orange.shade700,
                          ),
                          _buildDetailRow(
                            context,
                            icon: Icons.notes,
                            label: 'Notes:',
                            value: logData['notes'] ?? 'No notes',
                          ),
                        ],
                      ),
                      if (logData['isOnPeriod'] == true) ...[
                        _buildLogDetailCard(
                          context,
                          title: 'Period Tracking',
                          details: [
                            _buildDetailRow(
                              context,
                              icon: Icons.calendar_month,
                              label: 'Menstrual Day:',
                              value:
                                  (logData['menstrualDay'] ?? 'N/A').toString(),
                              valueColor: Colors.red.shade700,
                            ),
                            _buildDetailRow(
                              context,
                              icon: Icons.water_drop,
                              label: 'Period Flow:',
                              value: logData['periodFlow'] ?? 'N/A',
                              valueColor: Colors.red.shade700,
                            ),
                          ],
                        ),
                        _buildLogDetailCard(
                          context,
                          title: 'Symptoms Logged',
                          details: _buildSymptomsDetails(
                              context, logData['symptoms'] ?? {}),
                        ),
                      ] else ...[
                        _buildLogDetailCard(
                          context,
                          title: 'Fertility Tracking',
                          details: [
                            _buildDetailRow(
                              context,
                              icon: Icons.opacity,
                              label: 'Cervical Mucus:',
                              value: logData['cervicalMucus'] ?? 'N/A',
                              valueColor: Colors.blue.shade700,
                            ),
                            _buildDetailRow(
                              context,
                              icon: Icons.science_outlined,
                              label: 'OPK Result:',
                              value: logData['opkResult'] ?? 'N/A',
                              valueColor: Colors.purple.shade700,
                            ),
                            _buildDetailRow(
                              context,
                              icon: Icons.favorite,
                              label: 'Intercourse:',
                              value: (logData['intercourseToday'] ?? false)
                                  ? 'Yes'
                                  : 'No',
                              valueColor: Colors.pink.shade700,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Close',
                style: GoogleFonts.poppins(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper to build a card for a section of log details
  Widget _buildLogDetailCard(BuildContext context,
      {required String title, required List<Widget> details}) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    if (details.isEmpty)
      return const SizedBox.shrink(); // Don't show card if no details

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const Divider(height: 15),
            ...details,
          ],
        ),
      ),
    );
  }

  // Helper to build a single row for a detail
  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor, // Optional color for the value text
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 20,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                color: valueColor ??
                    Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to dynamically build symptom detail rows
  List<Widget> _buildSymptomsDetails(
      BuildContext context, Map<String, dynamic> symptoms) {
    final List<Widget> symptomWidgets = [];
    final Map<String, String> symptomLabels = {
      'fatigue': 'Fatigue',
      'acne': 'Acne',
      'cramps': 'Cramps',
      'headache': 'Headache',
      'bloating': 'Bloating',
    };
    final Map<String, IconData> symptomIcons = {
      'fatigue': Icons.hotel_outlined,
      'acne': Icons.auto_awesome_outlined,
      'cramps': Icons.sick_outlined,
      'headache': Icons.local_hospital_outlined,
      'bloating': Icons
          .bubble_chart_outlined, // Using a generic bubble icon for bloating
    };

    symptoms.forEach((key, value) {
      if (value == true) {
        // Only show symptoms that were logged as true
        symptomWidgets.add(_buildDetailRow(
          context,
          icon:
              symptomIcons[key] ?? Icons.check_circle_outline, // Fallback icon
          label: symptomLabels[key] ??
              key.replaceFirst(key[0], key[0].toUpperCase()), // Fallback label
          value: 'Yes',
          valueColor: Colors.green.shade700, // Green for positive symptom
        ));
      }
    });

    if (symptomWidgets.isEmpty) {
      symptomWidgets.add(_buildDetailRow(
        context,
        icon: Icons.check_box_outline_blank,
        label: 'No specific symptoms logged.',
        value: '',
        valueColor: Colors.grey.shade600,
      ));
    }

    return symptomWidgets;
  }

  @override
  Widget build(BuildContext context) {
    // Access the current theme's colorScheme
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: colorScheme.primary)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar:
          true, // Allows body to go behind transparent app bar
      appBar: AppBar(
        // Set the background color to match the Daily Log Screen's primary color
        backgroundColor: Colors.deepPurple
            .shade400, // Changed to match the DailyLogScreen's AppBar
        foregroundColor:
            Colors.white, // Keep text/icons white for good contrast
        elevation: 0, // No shadow for a flat look
        title: Text(
          'My Cycle Insights',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white, // Title color also white
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            tooltip: 'Cycle profile',
            onPressed: () => Navigator.of(context).pushNamed('/profile'),
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors
                  .deepPurple.shade50, // Match DailyLogScreen's gradient start
              Colors.purple.shade100, // Match DailyLogScreen's gradient middle
              Colors.deepPurple.shade200, // Match DailyLogScreen's gradient end
            ],
            stops: const [
              0.0,
              0.5,
              1.0
            ], // Keep the stops for consistent appearance
          ),
        ),
        child: SingleChildScrollView(
          // Ensure enough padding for FAB and bottom navigation bar, but not excessive
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top +
                kToolbarHeight, // Top padding for app bar
            bottom: 80.0 +
                MediaQuery.of(context)
                    .padding
                    .bottom, // FAB height + safe area bottom padding
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 10.0, 20.0, 0.0),
                child: Text(
                  'Hello, ${_userData?['name'] ?? AccountService.instance.currentUser?.email.split('@').first ?? 'User'}!',
                  style: GoogleFonts.playfairDisplay(
                    // Attractive style for greeting
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // White color for contrast
                  ),
                ),
              ),
              const SizedBox(height: 25),

              _buildCalendar(),
              const SizedBox(height: 25),

              if (_userData != null &&
                  (_predictedNextPeriodStart != null ||
                      _predictedOvulationDay != null))
                _buildPredictionSummaryCard(),
              const SizedBox(height: 20), // Extra space at bottom
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(
            MaterialPageRoute(
              builder: (context) => const DailyLogScreen(),
            ),
          )
              .then((_) {
            _fetchUserDataAndMakeInitialPrediction(); // Refresh data after returning from log screen
          });
        },
        tooltip: 'Log Data',
        backgroundColor: Colors.transparent, // Make FAB background transparent
        elevation: 0, // Remove default elevation
        child: Material(
          // Wrap Ink with Material
          elevation: 8.0, // Add the shadow here (adjust value as needed)
          borderRadius: BorderRadius.circular(50),
          color: Colors
              .transparent, // Make Material background transparent so gradient shows
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFD3A4F4),
                  Color(0xFF8A2BE2)
                ], // Lighter to Darker Purple
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.circular(50), // Make it perfectly round
            ),
            child: const Center(
              child: Icon(
                Icons.add,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: const Color(0xFFFFFFFF), // Slightly transparent white
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.home,
                  color: const Color(0xFF8A2BE2), size: 28), // Violet
              onPressed: () {
                // Already on home screen, maybe scroll to top
              },
            ),
            // ICON BUTTON FOR FOOD OPTIONS
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
            // Spacer for the FAB
            const SizedBox(width: 48),
            IconButton(
              icon: Icon(Icons.self_improvement,
                  color: Colors.grey.shade600,
                  size: 28), // Changed icon to self_improvement
              onPressed: () {
                // Navigate to your Meditation Screen
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SymptomSelectionScreen(),
                    settings: const RouteSettings(
                        name:
                            '/symptomSelection'), // <-- Replace with your MeditationScreen
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Card to display summary of cycle predictions
  Widget _buildPredictionSummaryCard() {
    // Access the current theme's colorScheme
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Calculate current cycle day
    int? currentCycleDay;
    double progressValue = 0.0;
    if (_lastPeriodStartDate != null &&
        _typicalCycleLength != null &&
        _typicalCycleLength! > 0) {
      currentCycleDay =
          DateTime.now().difference(_lastPeriodStartDate!).inDays + 1;
      progressValue = currentCycleDay / _typicalCycleLength!;
      progressValue =
          progressValue.clamp(0.0, 1.0); // Ensure value is between 0 and 1
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20.0),
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      // background gradient for the card
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.9),
              const Color(0xFFF3E5F5).withValues(alpha: 0.9), // Lightest Purple
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9)
                  .withValues(alpha: 0.5), // Lighter purple shadow
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Cycle Outlook',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary, // Use primary color for heading
              ),
            ),
            Divider(
                color: colorScheme.primary.withValues(alpha: 0.3),
                thickness: 1.5,
                height: 25),

            // --- New: Cycle Day and Progress Bar ---
            if (_lastPeriodStartDate != null &&
                _typicalCycleLength != null &&
                _typicalCycleLength! > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cycle Day: ${currentCycleDay ?? 'N/A'} / ${_typicalCycleLength ?? 'N/A'}',
                      style: GoogleFonts.montserrat(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progressValue,
                      backgroundColor: Colors.grey.shade300,
                      color:
                          colorScheme.primary, // Use primary color for progress
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            // --- End New Section ---

            _buildInfoRow(
                'Last Period Start:',
                _lastPeriodStartDate != null
                    ? DateFormat('MMM dd, yyyy').format(_lastPeriodStartDate!)
                    : 'N/A',
                Icons.calendar_today_rounded, // Calendar icon
                Colors.pink.shade400),
            _buildInfoRow(
                'Next Period Est.:',
                _predictedNextPeriodStart != null
                    ? DateFormat('MMM dd, yyyy')
                        .format(_predictedNextPeriodStart!)
                    : 'N/A',
                Icons.bloodtype_outlined, // Blood drop icon
                _predictedPeriodColor),
            _buildInfoRow(
                'Ovulation Est.:',
                _predictedOvulationDay != null
                    ? DateFormat('MMM dd, yyyy').format(_predictedOvulationDay!)
                    : 'N/A',
                Icons.egg_alt_outlined, // Egg icon
                _predictedOvulationTextColor // Use text color directly
                ),
            _buildInfoRow(
                'Fertile Window:',
                _predictedFertileWindow.isNotEmpty
                    ? '${DateFormat('MMM dd').format(_predictedFertileWindow.first)} - ${DateFormat('MMM dd, yyyy').format(_predictedFertileWindow.last)}'
                    : 'N/A',
                Icons.favorite_border_rounded, // Heart outline icon
                _predictedFertileTextColor // Use text color directly
                ),
            const SizedBox(height: 20),
            Text(
              'Note: These are initial estimates. Predictions will become more accurate as you log daily data!',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget to build a row for cycle info
  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 15),
          Text(
            '$label ',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: color, // Use the provided color for the value text
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right, // Align value to the right
            ),
          ),
        ],
      ),
    );
  }

  // Builds the TableCalendar widget
  Widget _buildCalendar() {
    // Access the current theme's colorScheme
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15.0),
      child: Card(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            color: const Color(0xFFEDE7F6), // Very light purple/lavender blush
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD1C4E9)
                    .withValues(alpha: 0.5), // Lighter purple shadow
                blurRadius: 10,
                spreadRadius: 3,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding:
              const EdgeInsets.all(8.0), // Padding inside card for calendar
          child: Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                rowHeight: 50.0,
                onDaySelected: (selectedDay, focusedDay) async {
                  // Made async
                  setState(() {
                    _focusedDay = focusedDay;
                  });

                  // Fetch and display log details for the selected day
                  final logData = await _fetchDailyLogForDate(selectedDay);
                  if (mounted) {
                    // Check if the widget is still in the widget tree
                    _showDailyLogDetails(context, selectedDay, logData);
                  }
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  markersAnchor: 0.9,
                  markersAlignment: Alignment.bottomCenter,
                  defaultTextStyle: GoogleFonts.montserrat(
                      color: Colors.grey.shade800, fontSize: 14),
                  weekendTextStyle: GoogleFonts.montserrat(
                      color: Colors.grey.shade600, fontSize: 14),
                  todayDecoration: const BoxDecoration(),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: GoogleFonts.montserrat(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    color: colorScheme
                        .primary, // Use primary color for calendar header
                  ),
                  leftChevronIcon: Icon(Icons.chevron_left_rounded,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      size: 30), // Lighter purple
                  rightChevronIcon: Icon(Icons.chevron_right_rounded,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      size: 30), // Lighter purple
                ),
                calendarBuilders: CalendarBuilders(
                  // TODAY BUILDER - Ensures today is always purple
                  todayBuilder: (context, day, focusedDay) {
                    return Container(
                      margin: const EdgeInsets.all(6.0),
                      decoration: BoxDecoration(
                        color: _todayFillColor, // Your specified purple fill
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _todayBorderColor,
                            width: 2.5), // Your specified purple border
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}', // This is where the day number is drawn
                        style: GoogleFonts.montserrat(
                          color: Colors.black87, // Dark text for readability
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    );
                  },
                  // DEFAULT BUILDER for all other days
                  defaultBuilder: (context, day, focusedDay) {
                    // Crucial: If the day is today, return null.
                    // This explicitly ensures the dedicated 'todayBuilder'
                    // is used for today, preventing any conflicts.
                    if (isSameDay(day, DateTime.now())) {
                      return null;
                    }

                    final markerTypes = _getMarkerTypesForDay(day);

                    Color textColor =
                        Colors.grey.shade800; // Default text color
                    Color? backgroundCircleColor;
                    FontWeight textFontWeight = FontWeight.normal;
                    BoxBorder?
                        border; // Not used for these markers, but kept for consistency

                    // Apply styles for period days (these are circles)
                    if (markerTypes
                            .contains(CalendarMarkerType.currentPeriod) &&
                        _lastPeriodStartDate != null) {
                      int periodDayIndex =
                          day.difference(_lastPeriodStartDate!).inDays;
                      backgroundCircleColor = _periodShades[
                          min(periodDayIndex, _periodShades.length - 1)];
                      textColor = Colors.white;
                      textFontWeight = FontWeight.bold;
                    } else if (markerTypes
                        .contains(CalendarMarkerType.predictedPeriod)) {
                      backgroundCircleColor = _predictedPeriodColor;
                      textColor = Colors.white;
                      textFontWeight = FontWeight.bold;
                    }

                    // Apply text colors for ovulation and fertile window (text-only markers on calendar)
                    // These apply only if no background circle color is already applied by period markers.
                    if (backgroundCircleColor == null) {
                      if (markerTypes
                          .contains(CalendarMarkerType.predictedOvulation)) {
                        textColor = _predictedOvulationTextColor;
                        textFontWeight = FontWeight.bold;
                      } else if (markerTypes
                          .contains(CalendarMarkerType.predictedFertile)) {
                        textColor = _predictedFertileTextColor;
                        textFontWeight = FontWeight.bold;
                      }
                    }

                    // Determine the final decoration for the day cell
                    BoxDecoration? dayDecoration;
                    if (backgroundCircleColor != null) {
                      dayDecoration = BoxDecoration(
                        color: backgroundCircleColor,
                        shape: BoxShape.circle,
                        border: border,
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.all(6.0),
                      decoration: dayDecoration,
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: GoogleFonts.montserrat(
                          color: textColor,
                          fontWeight: textFontWeight,
                          fontSize: 15,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Divider(
                  indent: 20,
                  endIndent: 20,
                  height: 1,
                  color: Colors.grey.shade300),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 15.0),
                child: InkWell(
                  onTap: () => _showLegendDialog(context),
                  borderRadius: BorderRadius.circular(15),
                  splashColor: colorScheme.primary
                      .withValues(alpha: 0.1), // Light purple splash
                  highlightColor: colorScheme.primary
                      .withValues(alpha: 0.05), // Very light purple highlight
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 24, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'View Calendar Legend',
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Shows the calendar legend in a dialog
  void _showLegendDialog(BuildContext context) {
    // Access the current theme's colorScheme
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          backgroundColor: Colors.white,
          title: Text(
            'Calendar Legend',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary, // Use primary color for legend title
              fontSize: 22,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendRow(
                  color: _periodShades[
                      2], // A mid-shade for general period representation
                  isCircle: true,
                  text: 'Current Period',
                ),
                _buildLegendRow(
                  color: _predictedPeriodColor,
                  isCircle: true,
                  text: 'Next Period',
                ),
                _buildLegendRow(
                  color: _predictedOvulationTextColor.withValues(
                      alpha: 0.2), // Light background for circle
                  border: Border.all(
                      color: _predictedOvulationTextColor, width: 2.0),
                  isCircle: true,
                  text: 'Ovulation',
                ),
                _buildLegendRow(
                  color: _predictedFertileTextColor.withValues(
                      alpha: 0.2), // Light background for circle
                  border:
                      Border.all(color: _predictedFertileTextColor, width: 2.0),
                  isCircle: true,
                  text: 'Fertile Window',
                ),
                _buildLegendRow(
                  color: _todayFillColor,
                  isCircle: true,
                  border: Border.all(color: _todayBorderColor, width: 2.0),
                  text: 'Today',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Got It!',
                style: GoogleFonts.montserrat(
                  color: colorScheme.primary, // Use primary color for button
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function for building legend rows
  Widget _buildLegendRow({
    Color? color, // Optional background color for circles
    required bool isCircle,
    required String text,
    Border? border, // Optional border for circles
  }) {
    // Access the current theme's colorScheme
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: isCircle
                ? BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: border,
                  )
                : BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: border,
                  ),
          ),
          const SizedBox(width: 16),
          Text(
            text,
            style: GoogleFonts.montserrat(
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
