import 'package:flutter/material.dart';
import 'package:femwise/services/account_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter
import 'package:google_fonts/google_fonts.dart'; // Import google_fonts

// Helper class to hold essential user profile data
class UserProfile {
  final DateTime? lastPeriodStartDate;
  final int? averagePeriodDuration; // in days
  final int? typicalCycleLength; // in days, added for completeness, though not directly used here, but good practice
  final String currentCycleStatus; // 'ON_PERIOD' or 'NOT_PERIOD'

  UserProfile({this.lastPeriodStartDate, this.averagePeriodDuration, this.typicalCycleLength, required this.currentCycleStatus});

  factory UserProfile.fromJson(Map<String, dynamic> data) {
    DateTime? lastPeriodDate;
    if (data['lastPeriodStartDate'] is String) {
      try {
        lastPeriodDate = DateFormat('yyyy-MM-dd').parse(data['lastPeriodStartDate']);
      } catch (e) {
        print('Error parsing lastPeriodStartDate string: ${data['lastPeriodStartDate']} - $e');
      }
    }

    return UserProfile(
      lastPeriodStartDate: lastPeriodDate,
      averagePeriodDuration: data['averagePeriodDuration'] as int?,
      typicalCycleLength: data['typicalCycleLength'] as int?,
      currentCycleStatus: data['currentCycleStatus'] ?? 'NOT_PERIOD', // Default to NOT_PERIOD
    );
  }
}

class DailyLogScreen extends StatefulWidget {
  const DailyLogScreen({super.key});

  @override
  State<DailyLogScreen> createState() => _DailyLogScreenState();
}

class _DailyLogScreenState extends State<DailyLogScreen> {
  final _formKey = GlobalKey<FormState>();

  // Daily Log data - ONLY what user observes and inputs DAILY
  String _periodFlow = 'None';
  String _cervicalMucus = 'Dry'; // Default to a valid dropdown item
  String _opkResult = 'Negative'; // Default to a valid dropdown item
  bool _intercourseToday = false;

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _menstrualDayController = TextEditingController(); // Controller for menstrual day input

  // General Symptoms (no mood swings here anymore)
  // These are boolean flags indicating presence/absence of a symptom.
  bool _fatigue = false;
  bool _acne = false;
  bool _cramps = false;
  bool _headache = false; // Updated to use generic medical icon
  bool _bloating = false;

  // New: Dedicated Mood variable (single selection)
  String _selectedMood = 'Neutral'; // Default mood

  bool _isLoading = true; // Start as loading
  UserProfile? _userProfile; // User profile data (including cycle status)

  bool _isOnPeriod = false; // Controls dynamic UI sections

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndLoadLog(); // Fetch user data and load today's log
  }

  @override
  void dispose() {
    _notesController.dispose();
    _menstrualDayController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserDataAndLoadLog() async {
    final user = AccountService.instance.currentUser;
    if (user == null) {
      setState(() { _isLoading = false; });
      return;
    }

    try {
      final userDoc = await AccountService.instance.getProfile();
      if (userDoc.isNotEmpty) {
        _userProfile = UserProfile.fromJson(userDoc);
        _isOnPeriod = (_userProfile!.currentCycleStatus == 'ON_PERIOD');
      } else {
        _userProfile = UserProfile(currentCycleStatus: 'NOT_PERIOD');
        _isOnPeriod = false;
      }
      await _loadDailyLogForToday();
    } catch (e) {
      print('Error fetching user data or daily log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _loadDailyLogForToday() async {
    final user = AccountService.instance.currentUser;
    if (user == null) return;

    try {
      final data = await AccountService.instance.getDailyLog(
          DateFormat('yyyy-MM-dd').format(DateTime.now()));

      if (data != null) {
        setState(() {
          _resetLogFields(); // Reset all fields first

          _isOnPeriod = data['isOnPeriod'] ?? false;
          _notesController.text = data['notes'] ?? '';
          _selectedMood = data['mood'] ?? 'Neutral'; // Load selected mood

          if (_isOnPeriod) {
            _periodFlow = data['periodFlow'] ?? 'None';
            _menstrualDayController.text = (data['menstrualDay'] ?? '').toString();

            Map<String, dynamic> symptoms = data['symptoms'] ?? {};
            _fatigue = symptoms['fatigue'] ?? false;
            _acne = symptoms['acne'] ?? false;
            _cramps = symptoms['cramps'] ?? false;
            _headache = symptoms['headache'] ?? false;
            _bloating = symptoms['bloating'] ?? false;

            _cervicalMucus = 'Dry';
            _opkResult = 'Negative';
            _intercourseToday = false;
          } else { // NOT_PERIOD
            _cervicalMucus = data['cervicalMucus'] == 'N/A' ? 'Dry' : (data['cervicalMucus'] ?? 'Dry');
            _opkResult = data['opkResult'] == 'N/A' ? 'Negative' : (data['opkResult'] ?? 'Negative');
            _intercourseToday = data['intercourseToday'] ?? false;

            _periodFlow = 'None';
            _menstrualDayController.clear();
            _fatigue = false; _acne = false;
            _cramps = false; _headache = false; _bloating = false;
          }
        });
      } else {
        _resetLogFields();
        _isOnPeriod = (_userProfile?.currentCycleStatus == 'ON_PERIOD');
      }
    } catch (e) {
      print('Error loading daily log for today: $e');
    }
  }

  void _resetLogFields() {
    setState(() {
      _periodFlow = 'None';
      _cervicalMucus = 'Dry';
      _opkResult = 'Negative';
      _intercourseToday = false;
      _notesController.clear();
      _menstrualDayController.clear();
      _fatigue = false;
      _acne = false;
      _cramps = false;
      _headache = false;
      _bloating = false;
      _selectedMood = 'Neutral'; // Reset mood to default
    });
  }

  Future<bool?> _showUnusualBleedingDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Unusual Bleeding in Last Cycle?'),
          content: const Text('Did you experience any unusual bleeding (spotting outside of your period) in the cycle that just ended?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Text('Yes'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDailyLog() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();

    final user = AccountService.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in.')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String docId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final Map<String, dynamic> logData = {
        'date': docId,
        'notes': _notesController.text.trim(),
        'isOnPeriod': _isOnPeriod,
        'mood': _selectedMood, // Save selected mood
      };

      Map<String, dynamic> userProfileUpdateData = {};

      if (_isOnPeriod) {
        logData['periodFlow'] = _periodFlow;
        logData['menstrualDay'] = int.tryParse(_menstrualDayController.text.trim());

        // Symptoms relevant during period
        logData['symptoms'] = {
          'fatigue': _fatigue, 'acne': _acne,
          'cramps': _cramps, 'headache': _headache, 'bloating': _bloating,
        };

        logData['cervicalMucus'] = 'N/A';
        logData['opkResult'] = 'N/A';
        logData['intercourseToday'] = false;

        if (int.tryParse(_menstrualDayController.text.trim()) == 1) {
          userProfileUpdateData['lastPeriodStartDate'] = docId;
          userProfileUpdateData['currentCycleStatus'] = 'ON_PERIOD';
        } else {
          userProfileUpdateData['currentCycleStatus'] = 'ON_PERIOD';
        }

      } else { // NOT_PERIOD
        logData['periodFlow'] = 'None';
        logData['menstrualDay'] = null;
        logData['cervicalMucus'] = _cervicalMucus;
        logData['opkResult'] = _opkResult;
        logData['intercourseToday'] = _intercourseToday;

        logData['symptoms'] = {}; // No specific period symptoms if not on period

        if (_userProfile?.currentCycleStatus == 'ON_PERIOD') {
          userProfileUpdateData['currentCycleStatus'] = 'NOT_PERIOD';
          bool? unusualBleedingForLastCycle = await _showUnusualBleedingDialog();
          // TODO (Next Step): Integrate calculation logic here.
        } else {
          userProfileUpdateData['currentCycleStatus'] = 'NOT_PERIOD';
        }
      }

      await AccountService.instance.saveDailyLog(
          docId, logData, userProfileUpdateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily log saved successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error saving daily log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save daily log: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      primary: Colors.deepPurple.shade400,
      secondary: Colors.purpleAccent.shade200,
      surface: Colors.deepPurple.shade50,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: Colors.black87,
    );

    return Theme(
      data: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        fontFamily: GoogleFonts.poppins().fontFamily,
        appBarTheme: AppBarTheme(
          // AppBar background now uses the primary color
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary, // White text for primary background
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimary, // White title for primary background
          ),
        ),
        cardTheme: CardTheme(
          color: colorScheme.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8.0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surface.withOpacity(0.7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          labelStyle: TextStyle(color: colorScheme.primary),
          hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.secondary;
          }),
          trackColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return colorScheme.primary.withOpacity(0.5);
            }
            return colorScheme.secondary.withOpacity(0.5);
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.onSurface.withOpacity(0.6);
          }),
          checkColor: MaterialStateProperty.all(colorScheme.onPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            elevation: 5,
          ),
        ),
        textTheme: TextTheme(
          titleLarge: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          titleMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
          bodyLarge: GoogleFonts.poppins(fontSize: 16, color: colorScheme.onSurface),
          bodyMedium: GoogleFonts.poppins(fontSize: 14, color: colorScheme.onSurface.withOpacity(0.8)),
          labelLarge: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Daily Log'), // Confirmed AppBar title
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
            : Container(
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
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: colorScheme.primary, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Logging for:',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                DateFormat('EEEE, MMM dd,yyyy').format(DateTime.now()),
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: _buildSwitchTile(
                        label: 'Are you on your period?',
                        value: _isOnPeriod,
                        onChanged: (bool newValue) {
                          setState(() {
                            _isOnPeriod = newValue;
                            _resetLogFields();
                            if (newValue) {
                              _periodFlow = 'Heavy';
                              _menstrualDayController.text = '1';
                            }
                          });
                        },
                        icon: Icons.water_drop_outlined,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // NEW: Mood Selector Section (always visible)
                  _buildSectionHeader(context, 'Daily Mood', colorScheme.primary),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildMoodSelector(context), // New mood selector
                    ),
                  ),
                  const SizedBox(height: 20),


                  if (_isOnPeriod) ...[
                    _buildSectionHeader(context, 'Period Tracking', colorScheme.primary),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _menstrualDayController,
                              decoration: const InputDecoration(
                                labelText: 'Menstrual Day (e.g., 1, 2, 3)',
                                hintText: 'Enter your period day number',
                                prefixIcon: Icon(Icons.numbers),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              validator: (value) {
                                if (_isOnPeriod && (value == null || value.isEmpty)) {
                                  return 'Please enter your menstrual day.';
                                }
                                if (_isOnPeriod && int.tryParse(value!) == null) {
                                  return 'Please enter a valid number.';
                                }
                                return null;
                              },
                              onSaved: (value) {},
                            ),
                            const SizedBox(height: 16),
                            _buildPeriodFlowSelector(context),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildSectionHeader(context, 'Daily Symptoms', colorScheme.primary),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildSymptomSelector(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    _buildSectionHeader(context, 'Fertility Tracking', colorScheme.primary),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildDropdownTile(
                              label: 'Cervical Mucus',
                              value: _cervicalMucus,
                              items: ['Dry', 'Sticky', 'Creamy', 'Wet', 'Eggwhite'],
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _cervicalMucus = newValue;
                                  });
                                }
                              },
                              icon: Icons.opacity,
                              color: Colors.blue.shade400,
                            ),
                            const SizedBox(height: 16),

                            _buildDropdownTile(
                              label: 'Ovulation Prediction Kit (OPK) Result',
                              value: _opkResult,
                              items: ['Negative', 'Low', 'High', 'Peak'],
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _opkResult = newValue;
                                  });
                                }
                              },
                              icon: Icons.science_outlined,
                              color: Colors.purple.shade400,
                            ),
                            const SizedBox(height: 16),

                            _buildSwitchTile(
                              label: 'Intercourse Today',
                              value: _intercourseToday,
                              onChanged: (bool newValue) {
                                setState(() {
                                  _intercourseToday = newValue;
                                });
                              },
                              icon: Icons.favorite_border,
                              color: Colors.pink.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  _buildSectionHeader(context, 'Notes', colorScheme.primary),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Any other observations or feelings?',
                          hintText: 'e.g., felt energetic, slight headache in the evening...',
                          prefixIcon: Icon(Icons.notes),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        minLines: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  ElevatedButton(
                    onPressed: _saveDailyLog,
                    child: const Text('Save Daily Log'),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  // New: Mood Selector
  Widget _buildMoodSelector(BuildContext context) {
    final Map<String, IconData> moodIcons = {
      'Very Happy': Icons.sentiment_very_satisfied,
      'Happy': Icons.sentiment_satisfied,
      'Neutral': Icons.sentiment_neutral,
      'Irritable': Icons.sentiment_dissatisfied,
      'Sad': Icons.sentiment_very_dissatisfied,
      'Anxious': Icons.mood_bad, // Using a more universal icon
    };

    final Map<String, String> moodLabels = {
      'Very Happy': 'Very Happy',
      'Happy': 'Happy',
      'Neutral': 'Neutral',
      'Irritable': 'Irritable',
      'Sad': 'Sad',
      'Anxious': 'Anxious',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'How are you feeling today?',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        SingleChildScrollView( // Use SingleChildScrollView for horizontal scroll if too many moods
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: moodIcons.keys.map((moodLevel) {
              bool isSelected = (_selectedMood == moodLevel);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMood = moodLevel;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0), // Add padding between icons
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.transparent, // Background of the container is now transparent
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            // Border uses primary color when selected, grey when not
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          moodIcons[moodLevel],
                          size: isSelected ? 34 : 30,
                          // Icon itself remains yellow shades
                          color: isSelected ? Colors.orange.shade900 : Colors.yellow.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        moodLabels[moodLevel]!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          // Text color also uses primary color when selected, or a muted grey
                          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }


  Widget _buildPeriodFlowSelector(BuildContext context) {
    final Map<String, IconData> flowIcons = {
      'None': Icons.do_not_disturb_on,
      'Spotting': Icons.water_drop_outlined,
      'Light': Icons.water_drop,
      'Medium': Icons.water_drop_sharp,
      'Heavy': Icons.bloodtype,
    };
    // Define explicit red shades for gradient effect
    final Map<String, Color> flowColors = {
      'None': Colors.grey.shade600, // No flow is grey
      'Spotting': Colors.red.shade300,
      'Light': Colors.red.shade500,
      'Medium': Colors.red.shade700,
      'Heavy': Colors.red.shade900,
    };
    final Map<String, String> flowLabels = {
      'None': 'None',
      'Spotting': 'Spot',
      'Light': 'Light',
      'Medium': 'Medium',
      'Heavy': 'Heavy',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'Daily Period Flow:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: flowIcons.keys.map((flowLevel) {
            bool isSelected = (_periodFlow == flowLevel);
            Color iconColor = flowColors[flowLevel]!;
            Color borderColor = isSelected ? iconColor : Colors.grey.shade300;
            Color backgroundColor = isSelected ? iconColor.withOpacity(0.1) : Colors.transparent;


            return GestureDetector(
              onTap: () {
                setState(() {
                  _periodFlow = flowLevel;
                });
              },
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      flowIcons[flowLevel],
                      size: isSelected ? 34 : 30,
                      color: iconColor, // Apply specific red shade
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    flowLabels[flowLevel]!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected ? iconColor : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Symptom Selector (Mood Swings removed from here)
  Widget _buildSymptomSelector(BuildContext context) {
    final Map<String, Map<String, dynamic>> symptomsData = {
      'fatigue': {'label': 'Fatigue', 'iconOff': Icons.hotel_outlined, 'iconOn': Icons.hotel, 'value': _fatigue, 'setter': (bool val) => setState(() => _fatigue = val)},
      'acne': {'label': 'Acne', 'iconOff': Icons.auto_awesome_outlined, 'iconOn': Icons.auto_awesome, 'value': _acne, 'setter': (bool val) => setState(() => _acne = val)},
      'cramps': {'label': 'Cramps', 'iconOff': Icons.sick_outlined, 'iconOn': Icons.sick, 'value': _cramps, 'setter': (bool val) => setState(() => _cramps = val)},
      'headache': {'label': 'Headache', 'iconOff': Icons.local_hospital_outlined, 'iconOn': Icons.local_hospital, 'value': _headache, 'setter': (bool val) => setState(() => _headache = val)}, // UPDATED ICONS
      'bloating': {'label': 'Bloating', 'iconOff': Icons.bubble_chart_outlined, 'iconOn': Icons.bubble_chart, 'value': _bloating, 'setter': (bool val) => setState(() => _bloating = val)},
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'Select any symptoms you experienced:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          children: symptomsData.keys.map((symptomKey) {
            final data = symptomsData[symptomKey]!;
            bool isSelected = data['value'];
            Function(bool) setter = data['setter'];

            return GestureDetector(
              onTap: () => setter(!isSelected),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      isSelected ? data['iconOn'] : data['iconOff'],
                      size: 30,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data['label'],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }


  Widget _buildSectionHeader(BuildContext context, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }

  Widget _buildDropdownTile({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<String>(
          value: value,
          onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: color),
          ),
          style: Theme.of(context).textTheme.bodyLarge,
          dropdownColor: Theme.of(context).colorScheme.surface,
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color color,
  }) {
    return SwitchListTile(
      title: Text(label, style: Theme.of(context).textTheme.labelLarge),
      value: value,
      onChanged: onChanged,
      activeColor: color,
      secondary: Icon(icon, color: color, size: 28),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
    );
  }
}