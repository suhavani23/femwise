import 'package:flutter/material.dart';
import 'dart:async'; // For Timer
import 'package:permission_handler/permission_handler.dart'; // For camera permission
import 'package:flutter/services.dart'; // For SystemChrome
import 'package:audioplayers/audioplayers.dart'; // Import for audio playback
import 'pose_match_widget.dart'; // Ensure this import path is correct

class GuideRunScreen extends StatefulWidget {
  final Map<String, dynamic> guide;

  const GuideRunScreen({super.key, required this.guide});

  @override
  State<GuideRunScreen> createState() => _GuideRunScreenState();
}

class _GuideRunScreenState extends State<GuideRunScreen> {
  late List<dynamic> steps;
  int currentStepIndex = 0;
  bool _cameraPermissionGranted = false;
  bool _permissionChecked = false;
  bool _manualMode = false;
  bool _showRepeatNextOption = false;
  late int
      _breathingStepRepeatedFromIndex; // To store the index of the pose before breathing

  // Audio player and its state
  late AudioPlayer _audioPlayer;
  bool _isMusicMuted = false;

  // Define a consistent purple color for the theme as MaterialColor to access shades
  static const MaterialColor _purpleThemeColor = Colors.deepPurple;

  @override
  void initState() {
    super.initState();
    steps = widget.guide['steps'];
    _checkCameraPermission();
    _initializeAudioPlayer();
    _forceLandscapeOrientation(); // Force landscape mode when this screen initializes
  }

  // Forces the screen to landscape mode
  void _forceLandscapeOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Revert to all orientations when this screen is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _audioPlayer.stop(); // Stop music when the screen is disposed
    _audioPlayer.dispose(); // Release audio player resources
    super.dispose();
  }

  void _initializeAudioPlayer() async {
    _audioPlayer = AudioPlayer();
    // Set looping to keep the music playing in the background
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      if (!mounted) return;
      await _audioPlayer.play(AssetSource('music.mp3'));
      if (!mounted) return;
      setState(() {
        _isMusicMuted = false; // Ensure it's not muted when it starts playing
      });
    } catch (e) {
      print('Error playing audio: $e');
      // Handle error, e.g., show a message to the user
    }
  }

  void _toggleMusicMute() async {
    try {
      if (_isMusicMuted) {
        await _audioPlayer.resume(); // Unmute
        print("Music unmuted.");
      } else {
        await _audioPlayer.pause(); // Mute
        print("Music muted.");
      }
      if (!mounted) return;
      setState(() {
        _isMusicMuted = !_isMusicMuted;
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Music is unavailable. You can continue the guide.')));
    }
  }

  Future<void> _checkCameraPermission() async {
    var granted = !steps.any((step) => step['type'] == 'pose');
    try {
      if (!granted) {
        final status = await Permission.camera.status;
        if (!mounted) return;
        granted =
            status.isGranted || (await Permission.camera.request()).isGranted;
      }
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() {
      _cameraPermissionGranted = granted;
      _permissionChecked = true;
    });
  }

  void _onStepCompleted() {
    if (!mounted || currentStepIndex >= steps.length) return;
    setState(() {
      currentStepIndex++;
    });

    if (currentStepIndex >= steps.length) {
      _showGuideCompletionDialog();
    }
  }

  void _onBreathingStepCompleted() {
    // Check if the previous step was a 'pose' type.
    // If the current step is the first step, there's no previous pose to repeat from.
    if (currentStepIndex > 0 && steps[currentStepIndex - 1]['type'] == 'pose') {
      _breathingStepRepeatedFromIndex = currentStepIndex - 1;
    } else {
      // If the previous step wasn't a pose, we can't repeat from a pose,
      // so we just advance normally.
      _breathingStepRepeatedFromIndex = -1; // Indicate no pose to repeat from
    }

    setState(() {
      _showRepeatNextOption = true;
    });
  }

  void _showGuideCompletionDialog() {
    _audioPlayer.stop(); // Stop music when guide is completed
    showDialog(
      context: context,
      barrierDismissible:
          false, // Prevents dialog from being dismissed by tapping outside
      builder: (_) => AlertDialog(
        title: Text(
          "🎉 Guide Completed",
          style: TextStyle(
              color: _purpleThemeColor,
              fontWeight: FontWeight.bold), // Purple title
        ),
        content: Text(
          "You've completed all steps successfully.",
          style: TextStyle(
              color: _purpleThemeColor.withValues(
                  alpha: 0.8)), // Slightly lighter purple content
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog
              Navigator.pop(context); // Pop the GuideRunScreen itself
            },
            child: const Text(
              "Done",
              style: TextStyle(color: _purpleThemeColor), // Purple button text
            ),
          )
        ],
      ),
    );
  }

  void _handleRepeat() {
    setState(() {
      _showRepeatNextOption = false;
      if (_breathingStepRepeatedFromIndex != -1) {
        currentStepIndex =
            _breathingStepRepeatedFromIndex; // Go back to the pose
      } else {
        // If there was no preceding pose, just re-do the breathing step
        // (this shouldn't happen if logic is always pose -> breathing)
        // For robustness, we could just stay on the current breathing step.
      }
    });
  }

  void _handleNext() {
    setState(() {
      _showRepeatNextOption = false;
      currentStepIndex++;
    });
    if (currentStepIndex >= steps.length) {
      _showGuideCompletionDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_cameraPermissionGranted && !_manualMode) {
      return Scaffold(
        appBar: AppBar(title: const Text("Permission Required")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Camera access enables pose matching. You can also follow the images and timers without a camera.',
                    textAlign: TextAlign.center),
                TextButton(
                    onPressed: _checkCameraPermission,
                    child: const Text('Retry camera permission')),
                TextButton(
                    onPressed: () => setState(() => _manualMode = true),
                    child: const Text('Continue without camera')),
              ],
            ),
          ),
        ),
      );
    }

    if (currentStepIndex >= steps.length) {
      return Scaffold(
        body: Center(
          child: Text(
            "Guide Finished",
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _purpleThemeColor), // Purple text for "Guide Finished"
          ),
        ),
      );
    }

    final step = steps[currentStepIndex];

    return Scaffold(
      // Removed AppBar here as the icon will be positioned directly in the Stack
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        step['title'] ?? 'Step ${currentStepIndex + 1}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _purpleThemeColor), // Purple step title
                      ),
                      const SizedBox(height: 20),
                      Text(step['instructions'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      if (step['type'] == 'pose' && !_manualMode)
                        Expanded(
                          child: PoseMatchCameraWidget(
                            key: ValueKey(currentStepIndex),
                            referenceImagePath: step['image'],
                            onPoseMatched: () {
                              print("Pose matched in GuideRunScreen");
                              _onStepCompleted();
                            },
                          ),
                        )
                      else // step['type'] == 'breathing'
                        Expanded(
                          child: BreathingStepWidget(
                            key: ValueKey(currentStepIndex),
                            step: step,
                            onStepCompleted: step['type'] == 'pose'
                                ? _onStepCompleted
                                : _onBreathingStepCompleted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Position the mute/unmute icon on top right
          Positioned(
            top: 16,
            left: 16,
            child: IconButton(
                tooltip: 'Leave guide',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: _purpleThemeColor)),
          ),
          Positioned(
            top: 16, // Adjust top padding as needed to be "a little top"
            right: 16, // Adjust right padding as needed
            child: IconButton(
              icon: Icon(
                _isMusicMuted ? Icons.volume_off : Icons.volume_up,
                color: _purpleThemeColor, // Purple icon for mute/unmute
                size: 28,
              ),
              onPressed: _toggleMusicMute,
            ),
          ),
          if (_showRepeatNextOption)
            RepeatNextOverlay(
              onRepeat: _handleRepeat,
              onNext: _handleNext,
              // Only enable repeat if there was a preceding pose
              canRepeat: _breathingStepRepeatedFromIndex != -1,
              purpleThemeColor:
                  _purpleThemeColor, // Pass the color to the overlay
            ),
        ],
      ),
    );
  }
}

class BreathingStepWidget extends StatefulWidget {
  final Map<String, dynamic> step;
  final VoidCallback onStepCompleted;

  const BreathingStepWidget({
    super.key,
    required this.step,
    required this.onStepCompleted,
  });

  @override
  State<BreathingStepWidget> createState() => _BreathingStepWidgetState();
}

class _BreathingStepWidgetState extends State<BreathingStepWidget> {
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Removed _setLandscapeOrientation() here as parent GuideRunScreen already handles it
    _remainingSeconds = widget.step['duration_minutes'] * 60;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        widget.onStepCompleted(); // Notify parent when breathing step is done
      }
      setState(() {
        _remainingSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // No need to revert orientation here, parent screen handles it
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.step['image'] != null)
            Image.asset(
              widget.step['image'],
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Remaining: ${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors
                      .white, // Keep timer white for contrast on dark background
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RepeatNextOverlay extends StatefulWidget {
  final VoidCallback onRepeat;
  final VoidCallback onNext;
  final bool canRepeat; // New parameter to indicate if repeat is an option
  final MaterialColor purpleThemeColor; // Changed type to MaterialColor

  const RepeatNextOverlay({
    super.key,
    required this.onRepeat,
    required this.onNext,
    this.canRepeat = true, // Default to true if not specified
    required this.purpleThemeColor, // Required for theme color
  });

  @override
  State<RepeatNextOverlay> createState() => _RepeatNextOverlayState();
}

class _RepeatNextOverlayState extends State<RepeatNextOverlay> {
  int _countdown = 10;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    _startOverlayTimer();
  }

  void _startOverlayTimer() {
    _overlayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        widget.onNext(); // Automatically move to next after 10 seconds
      }
      setState(() {
        _countdown--;
      });
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54, // Semi-transparent black background
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${_countdown} seconds to choose...',
              style: TextStyle(
                fontSize: 24,
                color: widget.purpleThemeColor, // Purple text for countdown
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.canRepeat
                      ? () {
                          _overlayTimer?.cancel();
                          widget.onRepeat();
                        }
                      : null, // Disable button if canRepeat is false
                  icon: const Icon(Icons.replay),
                  label: const Text('Repeat', style: TextStyle(fontSize: 20)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    backgroundColor: widget.canRepeat
                        ? widget.purpleThemeColor
                        : Colors
                            .grey, // Purple button if enabled, grey if disabled
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _overlayTimer?.cancel();
                    widget.onNext();
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next', style: TextStyle(fontSize: 20)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    backgroundColor: widget
                        .purpleThemeColor.shade700, // Access shade700 correctly
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
