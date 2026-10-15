import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Remove the global 'late List<CameraDescription> _cameras;' declaration
// Remove the 'Future<void> main() async { ... }' function
// Remove the 'class MyApp extends StatelessWidget { ... }'

class ImageToTextScreen extends StatefulWidget {
  const ImageToTextScreen({super.key});

  @override
  State<ImageToTextScreen> createState() => _ImageToTextScreenState();
}

class _ImageToTextScreenState extends State<ImageToTextScreen> {
  String _extractedText = '';
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String _backendResponse = '';

  CameraController? _cameraController;
  Future<void>? _initializeCameraControllerFuture;

  // Declare _cameras as an instance variable within the State class
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Initialize _cameras here by getting available cameras
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _extractedText = "No cameras found on this device.";
          });
        }
        return;
      }
      final firstCamera = _cameras.first;

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeCameraControllerFuture = _cameraController!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {}); // Rebuild to display camera preview
      }).catchError((Object e) {
        if (e is CameraException) {
          switch (e.code) {
            case 'CameraAccessDenied':
              if (mounted) {
                setState(() {
                  _extractedText = 'Camera access denied. Please grant permission in settings.';
                });
              }
              break;
            default:
              if (mounted) {
                setState(() {
                  _extractedText = 'Error initializing camera: ${e.description}';
                });
              }
              print('Error initializing camera: ${e.description}');
              break;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _extractedText = 'Error getting available cameras: $e';
        });
      }
      print('Error getting available cameras: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _sendTextToFastAPI(String textToSend) async {
    setState(() {
      _isProcessing = true;
      _backendResponse = 'Sending text to backend...';
    });

    final Uri uri = Uri.parse('http://192.168.68.220:8000/extract_ingredients');

    try {
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'text': textToSend,
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);

        if (responseBody['extracted_ingredients'] is List) {
          List<dynamic> ingredients = responseBody['extracted_ingredients'];
          String formattedResponse = 'Backend Response:\n';
          for (var item in ingredients) {
            formattedResponse += '  - ${item['original_extracted_name']}:\n';
            if (item['is_exact_match']) {
              formattedResponse += '    Matched Name: ${item['name']}\n';
            } else if (item['name'] != item['original_extracted_name'] && item['name'] != null) {
              formattedResponse += '    Closest Match: ${item['name']}\n';
            } else {
              formattedResponse += '    Status: ${item['name']} (not found)\n';
            }
            formattedResponse += '    Effects: ${item['effects'] ?? 'N/A'}\n';
            formattedResponse += '    Verdict: ${item['verdict'] ?? 'N/A'}\n';
          }
          _backendResponse = formattedResponse;
        } else {
          _backendResponse = 'Backend acknowledged: ${responseBody['message'] ?? 'Success'}';
        }

        setState(() {});
        print('Text sent successfully! Backend acknowledged.');
        print('Backend response body: ${response.body}');
      } else {
        setState(() {
          _backendResponse = 'Error from backend: ${response.statusCode} - ${response.body}';
        });
        print('Failed to send text. Status code: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _backendResponse = 'Network/API error: $e';
      });
      print('Error sending text to backend: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _takePictureAndRecognizeText() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (mounted) {
        setState(() {
          _extractedText = 'Camera not initialized.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _extractedText = 'Capturing image...';
        _backendResponse = '';
      });
    }

    try {
      final XFile imageFile = await _cameraController!.takePicture();

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
            activeControlsWidgetColor: Theme.of(context).colorScheme.secondary,
            cropGridColor: Colors.white,
          ),
          IOSUiSettings(
            title: 'Crop Image',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Back',
            aspectRatioLockEnabled: false,
            rotateButtonsHidden: false,
            resetButtonHidden: false,
          ),
          WebUiSettings(
            context: context,
          ),
        ],
      );

      if (croppedFile != null) {
        await _processImageForText(croppedFile.path);
      } else {
        if (mounted) {
          setState(() {
            _extractedText = 'Image capture cancelled or not cropped.';
            _backendResponse = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extractedText = 'Error capturing image: $e';
          _backendResponse = '';
        });
      }
      print('Error capturing image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pickImageFromGalleryAndRecognizeText() async {
    if (mounted) {
      setState(() {
        _isProcessing = true;
        _extractedText = '';
        _backendResponse = '';
      });
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: Theme.of(context).colorScheme.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: 'Crop Image',
              doneButtonTitle: 'Done',
              cancelButtonTitle: 'Cancel',
              aspectRatioLockEnabled: false,
              rotateButtonsHidden: false,
              resetButtonHidden: false,
            ),
            WebUiSettings(
              context: context,
            ),
          ],
        );

        if (croppedFile != null) {
          await _processImageForText(croppedFile.path);
        } else {
          if (mounted) {
            setState(() {
              _extractedText = 'Image picking cancelled or not cropped.';
              _backendResponse = '';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _extractedText = 'Image picking cancelled.';
            _backendResponse = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extractedText = 'Error picking image from gallery: $e';
          _backendResponse = '';
        });
      }
      print('Error picking image from gallery: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _processImageForText(String imagePath) async {
    try {
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      if (mounted) {
        setState(() {
          _extractedText = recognizedText.text.isEmpty
              ? 'No text found or recognized.'
              : recognizedText.text;
        });

        if (_extractedText.isNotEmpty && _extractedText != 'No text found or recognized.') {
          await _sendTextToFastAPI(_extractedText);
        } else {
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _backendResponse = 'No text to send to backend.';
            });
          }
        }
      }
      textRecognizer.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _extractedText = 'Error during text recognition: $e';
          _backendResponse = 'Error during text recognition.';
        });
      }
      print('Error during text recognition: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      appBar: AppBar(
        title: Text(
          'Ingredients Scanner',
          style: GoogleFonts.montserrat(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      body: FutureBuilder<void>(
        future: _initializeCameraControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_cameraController == null || !_cameraController!.value.isInitialized) {
              return Center(
                child: Text(
                  _extractedText.isNotEmpty
                      ? _extractedText
                      : "Camera not available or permissions not granted.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(fontSize: 18, color: Theme.of(context).colorScheme.onPrimary),
                ),
              );
            }
            return Column(
              children: <Widget>[
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: AspectRatio(
                          aspectRatio: _cameraController!.value.aspectRatio,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isProcessing
                                ? null
                                : () => _takePictureAndRecognizeText(),
                            child: Center(
                              child: _isProcessing
                                  ? CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary)
                                  : Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Tap anywhere to capture image',
                                    style: GoogleFonts.montserrat(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: _isProcessing
                          ? CircularProgressIndicator(color: Theme.of(context).colorScheme.onSurface)
                          : SingleChildScrollView(
                        child: SelectableText(
                          _extractedText.isEmpty
                              ? 'Place the camera over the text and tap to scan.'
                              : (_backendResponse.isEmpty
                              ? _extractedText
                              : 'Extracted:\n$_extractedText\n\n$_backendResponse'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary));
          }
        },
      ),
    );
  }
}