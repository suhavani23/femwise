import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:http/http.dart' as http; // For making HTTP requests
import 'package:path/path.dart' as path; // For handling file paths
import 'dart:convert'; // For JSON encoding/decoding
import 'package:http_parser/http_parser.dart' show MediaType; // Added for explicit content type
import 'dart:math' as math; // For PieChartPainter

// Temporary main function to run this screen directly
void main() {
  runApp(const MyAppForCookedFood());
}

class MyAppForCookedFood extends StatelessWidget {
  const MyAppForCookedFood({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cooked Food Test App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple, // You can customize your theme here
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
      ),
      home: const FoodCaptureScreen(), // This correctly matches the class name below
    );
  }
}

class FoodCaptureScreen extends StatefulWidget {
  const FoodCaptureScreen({super.key});

  @override
  State<FoodCaptureScreen> createState() => _FoodCaptureScreenState();
}

class _FoodCaptureScreenState extends State<FoodCaptureScreen> {
  File? _imageFile; // Stores the selected image
  final TextEditingController _dishNameController = TextEditingController();
  String _backendResponse = "No analysis yet. Upload food to see results!";
  bool _isLoading = false; // To show loading indicator during submission

  // New state variables for detailed analysis from packed_foods_scan
  String _pcosVerdictAndExplanation = '';
  List<dynamic> _ingredientsSummary = [];
  List<dynamic> _extractedIngredientDetails = []; // To store raw ingredient details
  bool _showExplanationDialog = false;

  final ImagePicker _picker = ImagePicker(); // Image picker instance

  // Function to pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _backendResponse = "Ready to analyze!"; // Reset message
        // Reset previous analysis results
        _pcosVerdictAndExplanation = '';
        _ingredientsSummary = [];
        _extractedIngredientDetails = [];
        _showExplanationDialog = false;
      });
    }
  }

  // Function to send data to FastAPI backend
  Future<void> _uploadFoodData() async {
    if (_imageFile == null || _dishNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image and enter a dish name.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _backendResponse = "Analyzing your food...";
      // Clear previous results while processing
      _pcosVerdictAndExplanation = '';
      _ingredientsSummary = [];
      _extractedIngredientDetails = [];
      _showExplanationDialog = false;
    });

    final uri = Uri.parse('http://192.168.1.100:8000/upload_food_data/'); // <<< VERIFY THIS IP!
    var request = http.MultipartRequest('POST', uri);

    try {
      // Determine the MIME type based on file extension
      String fileExtension = path.extension(_imageFile!.path).toLowerCase();
      String? mimeType;

      if (fileExtension == '.jpg' || fileExtension == '.jpeg') {
        mimeType = 'image/jpeg';
      } else if (fileExtension == '.png') {
        mimeType = 'image/png';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unsupported image format. Please use JPG/JPEG or PNG.')),
        );
        setState(() {
          _isLoading = false;
          _backendResponse = "Error: Unsupported image format.";
        });
        return; // Stop function execution
      }

      // Add image file to the request with explicit content type
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // This 'file' key MUST match the FastAPI @app.post parameter name (file: UploadFile)
          _imageFile!.path,
          filename: path.basename(_imageFile!.path),
          contentType: MediaType('image', fileExtension.substring(1)), // e.g., image/jpeg or image/png
        ),
      );

      // Add dish name field to the request
      request.fields['dish_name'] = _dishNameController.text.trim(); // This 'dish_name' key MUST match FastAPI @app.post parameter name (dish_name: str = Form(...))

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        setState(() {
          _pcosVerdictAndExplanation = responseData['pcos_verdict_and_explanation'] ?? 'No PCOS verdict provided.';
          _ingredientsSummary = responseData['ingredients_summary'] ?? [];
          _extractedIngredientDetails = responseData['extracted_ingredient_details'] ?? [];

          // Update backend response to show verdict immediately
          final parsed = _parseBackendResponse(_pcosVerdictAndExplanation);
          _backendResponse = 'Verdict: ${parsed['verdict']!}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food data uploaded successfully!')),
        );
      } else {
        // Handle non-200 status codes (e.g., 400, 500)
        String errorMessage = 'Failed to upload data. Status: ${response.statusCode}';
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData.containsKey('detail')) {
            errorMessage += '\nDetail: ${errorData['detail']}';
          }
        } catch (e) {
          // If response body is not JSON, use the raw body
          errorMessage += '\nRaw response: ${response.body}';
        }
        setState(() {
          _backendResponse = errorMessage;
          _pcosVerdictAndExplanation = '';
          _ingredientsSummary = [];
          _extractedIngredientDetails = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      // Handle network-related errors (e.g., connection timed out, no internet)
      setState(() {
        _backendResponse = 'Network Error: $e';
        _pcosVerdictAndExplanation = '';
        _ingredientsSummary = [];
        _extractedIngredientDetails = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
      print('HTTP request error: $e'); // Print detailed error to console for debugging
    } finally {
      setState(() {
        _isLoading = false; // Always stop loading indicator
      });
    }
  }

  @override
  void dispose() {
    _dishNameController.dispose();
    super.dispose();
  }

  // Helper functions and widgets copied from pack_foods_scan.dart
  Map<String, String> _parseBackendResponse(String response) {
    String verdict = 'N/A';
    String explanation = response;

    final verdictMatch = RegExp(r'Verdict: (.*?)\n').firstMatch(response);
    final explanationMatch = RegExp(r'Explanation: (.*)', dotAll: true).firstMatch(response);

    if (verdictMatch != null) {
      verdict = verdictMatch.group(1)?.trim() ?? 'N/A';
    }
    if (explanationMatch != null) {
      explanation = explanationMatch.group(1)?.trim() ?? 'No detailed explanation provided.';
    }

    return {
      'verdict': verdict,
      'explanation': explanation,
    };
  }

  // KEEP THESE COLORS AS IS (as per user request)
  Color _getVerdictColor(String verdict) {
    switch (verdict.toLowerCase()) {
      case 'recommended':
      case 'safe':
      case 'good': // Added 'good' for consistency
        return Colors.green.shade700;
      case 'generally recommended':
      case 'moderate':
        return Colors.orange.shade700;
      case 'not recommended':
      case 'potentially harmful':
      case 'harmful':
      case 'bad': // Added 'bad' for consistency
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  IconData _getVerdictIcon(String verdict) {
    switch (verdict.toLowerCase()) {
      case 'recommended':
      case 'safe':
      case 'good':
        return Icons.check_circle_outline;
      case 'generally recommended':
      case 'moderate':
        return Icons.info_outline;
      case 'not recommended':
      case 'potentially harmful':
      case 'harmful':
      case 'bad':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildBackendResponseCard(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // Use _pcosVerdictAndExplanation for verdict display if available, otherwise _backendResponse
    final parsedResponse = _parseBackendResponse(_pcosVerdictAndExplanation.isNotEmpty ? _pcosVerdictAndExplanation : _backendResponse);
    final String verdict = parsedResponse['verdict']!;
    final Color verdictColor = _getVerdictColor(verdict);
    final IconData verdictIcon = _getVerdictIcon(verdict);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6), // Use theme surface color
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis Status & Verdict',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 15),
            if (_isLoading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        _backendResponse,
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          color: Colors.black87,
                          fontStyle: FontStyle.italic,
                        ),
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              )
            else if (_pcosVerdictAndExplanation.isNotEmpty)
            // This is the verdict display, styled to match the image
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  color: verdictColor.withOpacity(0.1), // Light background color
                  borderRadius: BorderRadius.circular(12), // Changed to 12 for blunt edges
                  border: Border.all(color: verdictColor, width: 1.5), // Colored border
                  boxShadow: [ // Subtle shadow for depth
                    BoxShadow(
                      color: verdictColor.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // Center the content
                  children: [
                    Icon(
                      verdictIcon,
                      color: verdictColor,
                      size: 30, // Slightly larger icon
                    ),
                    const SizedBox(width: 12), // Increased spacing
                    Flexible( // Use Flexible to prevent overflow
                      child: Text(
                        'Verdict: ${verdict.capitalize()}', // Capitalize verdict for display
                        style: GoogleFonts.montserrat(
                          fontSize: 20, // Larger font size
                          fontWeight: FontWeight.bold,
                          color: verdictColor,
                        ),
                        textAlign: TextAlign.center, // Center text
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  _backendResponse,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientPieChart(BuildContext context) {
    if (_ingredientsSummary.isEmpty) {
      return const SizedBox.shrink();
    }

    Map<String, int> categoryCounts = {
      'good': 0,
      'bad': 0,
      'moderate': 0,
      'unknown': 0,
    };

    for (var ingredientData in _ingredientsSummary) {
      if (ingredientData.length >= 2) {
        String classification = ingredientData[1].toString().toLowerCase();

        if (classification == 'good' || classification == 'safe') {
          categoryCounts['good'] = (categoryCounts['good'] ?? 0) + 1;
        } else if (classification == 'bad' || classification == 'harmful') {
          categoryCounts['bad'] = (categoryCounts['bad'] ?? 0) + 1;
        } else if (classification == 'moderate' || classification == 'generally recommended' || classification == 'potentially bad if processed') {
          categoryCounts['moderate'] = (categoryCounts['moderate'] ?? 0) + 1;
        } else {
          categoryCounts['unknown'] = (categoryCounts['unknown'] ?? 0) + 1;
        }
      }
    }

    int totalCount = 0;
    categoryCounts.values.forEach((count) => totalCount += count);

    if (totalCount == 0) {
      return const SizedBox.shrink();
    }

    // KEEP THESE COLORS AS IS (as per user request)
    Map<String, Color> categoryColors = {
      'good': Colors.green.shade600,
      'bad': Colors.red.shade600,
      'moderate': Colors.orange.shade600,
      'unknown': Colors.grey.shade400,
    };

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(top: 20.0),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6), // Use theme surface color
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingredient Classification Breakdown',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: PieChartPainter(
                    categoryCounts: categoryCounts,
                    categoryColors: categoryColors,
                    totalCount: totalCount,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildLegend(categoryCounts, categoryColors, totalCount),
          ],
        ),
      ),
    );
  }

  // KEEP THESE COLORS AS IS (as per user request)
  Color _getIngredientTagColor(String classification) {
    switch (classification.toLowerCase()) {
      case 'good':
      case 'safe':
        return Colors.green.shade100;
      case 'bad':
      case 'harmful':
        return Colors.red.shade100;
      case 'moderate':
      case 'generally recommended':
      case 'potentially bad if processed':
        return Colors.orange.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  // KEEP THESE COLORS AS IS (as per user request)
  Color _getIngredientTagBorderColor(String classification) {
    switch (classification.toLowerCase()) {
      case 'good':
      case 'safe':
        return Colors.green.shade400;
      case 'bad':
      case 'harmful':
        return Colors.red.shade400;
      case 'moderate':
      case 'generally recommended':
      case 'potentially bad if processed':
        return Colors.orange.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  // KEEP THESE COLORS AS IS (as per user request)
  Color _getIngredientTagTextColor(String classification) {
    switch (classification.toLowerCase()) {
      case 'good':
      case 'safe':
        return Colors.green.shade400;
      case 'bad':
      case 'harmful':
        return Colors.red.shade400;
      case 'moderate':
      case 'generally recommended':
      case 'potentially bad if processed':
        return Colors.orange.shade400;
      default:
        return Colors.grey.shade800;
    }
  }

  Widget _buildLegend(Map<String, int> categoryCounts, Map<String, Color> categoryColors, int totalCount) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: categoryCounts.entries.map((entry) {
        if (entry.value == 0) return const SizedBox.shrink();
        final percentage = (entry.value / totalCount * 100).toStringAsFixed(1);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                color: categoryColors[entry.key],
                margin: const EdgeInsets.only(right: 8),
              ),
              Text(
                '${entry.key.capitalize()}: ${entry.value} ($percentage%)',
                style: GoogleFonts.montserrat(fontSize: 14, color: colorScheme.onSurface),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIngredientTags(BuildContext context) {
    if (_ingredientsSummary.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 20.0),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6), // Use theme surface color
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recognized Highly Contributing Ingredients',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _ingredientsSummary.map((ingredientData) {
                final String ingredientName = ingredientData[0].toString().capitalize();
                final String classification = ingredientData[1].toString().toLowerCase();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    color: _getIngredientTagColor(classification),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: _getIngredientTagBorderColor(classification), width: 1.0),
                  ),
                  child: Text(
                    ingredientName,
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _getIngredientTagTextColor(classification),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to build formatted explanation text
  List<InlineSpan> _buildFormattedTextSpans(String text, ColorScheme colorScheme) {
    final List<InlineSpan> spans = [];
    // Regex to find keywords. Added more PCOS-related terms.
    final RegExp keywordRegex = RegExp(
      r'\b(good|harmful|bad|moderate|recommended|PCOS|insulin resistance|inflammation|hormonal balance|blood sugar|processed foods|whole foods|nutrients|vitamins|minerals|fiber|healthy fats|unhealthy fats|sugar|refined grains|dairy|gluten|avoid|limit|beneficial|detrimental|syndrome|diet|lifestyle)\b',
      caseSensitive: false,
    );
    text.splitMapJoin(
      keywordRegex,
      onMatch: (Match match) {
        final String keyword = match.group(0)!;
        Color? keywordColor;
        FontWeight fontWeight = FontWeight.bold;
        // Determine color based on keyword sentiment
        if (['good', 'recommended', 'beneficial', 'healthy fats', 'whole foods', 'nutrients', 'vitamins', 'minerals', 'fiber', 'lifestyle'].contains(keyword.toLowerCase())) {
          keywordColor = Colors.green.shade700;
        } else if (['harmful', 'bad', 'not recommended', 'detrimental', 'sugar', 'processed foods', 'unhealthy fats', 'refined grains', 'avoid'].contains(keyword.toLowerCase())) {
          keywordColor = Colors.red.shade700;
        } else if (['moderate', 'limit', 'dairy', 'gluten', 'potentially harmful'].contains(keyword.toLowerCase())) {
          keywordColor = Colors.orange.shade700;
        } else {
          // Default to onSurface for other matched keywords, no purple
          keywordColor = colorScheme.onSurface;
          fontWeight = FontWeight.normal; // Not bold if not a specific sentiment keyword
        }
        spans.add(
          TextSpan(
            text: keyword,
            style: GoogleFonts.montserrat(
              color: keywordColor,
              fontWeight: fontWeight,
              fontStyle: FontStyle.italic, // All keywords are italic
            ),
          ),
        );
        return ''; // Return empty string to indicate match was handled
      },
      onNonMatch: (String nonMatch) {
        spans.add(
          TextSpan(
            text: nonMatch,
            style: GoogleFonts.montserrat(
              color: colorScheme.onSurface, // Default text color, no purple
              fontSize: 15,
            ),
          ),
        );
        return ''; // Return empty string to indicate non-match was handled
      },
    );
    return spans;
  }

  Widget _buildExplanationDialog(BuildContext context) {
    final parsedResponse = _parseBackendResponse(_pcosVerdictAndExplanation);
    final String explanation = parsedResponse['explanation']!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // Split the explanation into paragraphs or points based on newlines
    final List<String> explanationPoints = explanation.split('\n').where((s) => s.trim().isNotEmpty).toList();

    return AlertDialog(
      title: Text(
        'Detailed PCOS Explanation',
        style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: colorScheme.primary),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display each explanation point with a bullet point
            ...explanationPoints.map((point) {
              // Check if the point starts with "Conclusion:" and if so, don't add a bullet
              if (point.trim().toLowerCase().startsWith('conclusion:')) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    point,
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold, // Make conclusion bold
                      fontSize: 15,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }
              // Skip "Verdict:" and "Explanation:" lines if they appear as points
              if (point.trim().toLowerCase().startsWith('verdict:') || point.trim().toLowerCase().startsWith('explanation:')) {
                return const SizedBox.shrink(); // Hide this point
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorScheme.secondary, // Use theme secondary color for bullet points
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: _buildFormattedTextSpans(point, colorScheme),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _showExplanationDialog = false;
            });
          },
          child: Text(
            'Close',
            style: GoogleFonts.montserrat(color: colorScheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildExplanationAndRawTextCard(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final parsedResponse = _parseBackendResponse(_pcosVerdictAndExplanation);
    final bool hasDetailedExplanation = _pcosVerdictAndExplanation.isNotEmpty && parsedResponse['explanation']!.isNotEmpty;

    if (!hasDetailedExplanation) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 20.0),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6), // Use theme surface color
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detailed Information',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            if (hasDetailedExplanation) ...[
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.center,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showExplanationDialog = true;
                    });
                  },
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  label: Text(
                    'View Detailed Explanation',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.shade400,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Capture Your Food',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 20,
            bottom: 20.0 + MediaQuery.of(context).padding.bottom,
            left: 20,
            right: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Removed the "Upload a photo of your dish!" text here
              _buildImageInputCard(context),
              const SizedBox(height: 20),
              _buildDishNameInputCard(context),
              const SizedBox(height: 20),
              // ADDING NEW UI ELEMENTS BELOW DISH NAME INPUT IN THE SPECIFIED ORDER
              _buildBackendResponseCard(context), // Analysis status and verdict
              if (!_isLoading && _ingredientsSummary.isNotEmpty)
                _buildIngredientPieChart(context),
              if (!_isLoading && _ingredientsSummary.isNotEmpty)
                _buildIngredientTags(context),
              _buildExplanationAndRawTextCard(context),
              // End of new UI elements
              const SizedBox(height: 80), // Space for FAB
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _uploadFoodData, // Disable when loading
        tooltip: 'Upload Food Data',
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Material(
          elevation: 8.0,
          borderRadius: BorderRadius.circular(50),
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isLoading ? [Colors.grey.shade400, Colors.grey.shade600] // Grey out when loading
                    : [const Color(0xFFD3A4F4), const Color(0xFF8A2BE2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Center(
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(
                Icons.cloud_upload_outlined, // Changed icon for clarity
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // Center the FAB
      // Conditionally show the detailed explanation dialog
      bottomSheet: _showExplanationDialog
          ? Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showExplanationDialog = false;
                });
              },
              child: Container(
                color: Colors.black.withOpacity(0.5), // Semi-transparent overlay
              ),
            ),
          ),
          Center(
            child: _buildExplanationDialog(context),
          ),
        ],
      )
          : null,
    );
  }

  Widget _buildImageInputCard(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Dish Photo',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300, width: 1),
                image: _imageFile != null
                    ? DecorationImage(
                  image: FileImage(_imageFile!),
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: _imageFile == null
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                    Text(
                      'No image selected',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
                  : null,
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                    label: Text(
                      'Camera',
                      style: GoogleFonts.montserrat(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
                    label: Text(
                      'Gallery',
                      style: GoogleFonts.montserrat(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDishNameInputCard(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: const Color(0xFFEDE7F6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD1C4E9).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dish Name',
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _dishNameController,
              decoration: InputDecoration(
                hintText: 'e.g., Chicken Curry, Vegetable Stir-fry',
                hintStyle: GoogleFonts.montserrat(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              ),
              style: GoogleFonts.montserrat(fontSize: 16, color: Colors.black87),
              cursorColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// PieChartPainter class (copied from pack_foods_scan.dart)
class PieChartPainter extends CustomPainter {
  final Map<String, int> categoryCounts;
  final Map<String, Color> categoryColors;
  final int totalCount;

  PieChartPainter({
    required this.categoryCounts,
    required this.categoryColors,
    required this.totalCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: size.shortestSide / 2);
    double startAngle = -math.pi / 2;

    categoryCounts.forEach((category, count) {
      if (count > 0) {
        final sweepAngle = (count / totalCount) * 2 * math.pi;
        final paint = Paint()
          ..color = categoryColors[category] ?? Colors.black
          ..style = PaintingStyle.fill;

        canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
        startAngle += sweepAngle;
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is PieChartPainter) {
      return oldDelegate.categoryCounts != categoryCounts ||
          oldDelegate.categoryColors != categoryColors ||
          oldDelegate.totalCount != totalCount;
    }
    return false;
  }
}

// Extension for String capitalization (copied from pack_foods_scan.dart)
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return this;
    }
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}