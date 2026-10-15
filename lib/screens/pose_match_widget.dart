import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class PoseMatchCameraWidget extends StatefulWidget {
  final String referenceImagePath;
  final VoidCallback onPoseMatched;

  const PoseMatchCameraWidget({
    super.key,
    required this.referenceImagePath,
    required this.onPoseMatched,
  });

  @override
  State<PoseMatchCameraWidget> createState() => _PoseMatchCameraWidgetState();
}

class _PoseMatchCameraWidgetState extends State<PoseMatchCameraWidget> {
  late CameraController controller;
  late Interpreter interpreter;
  bool isProcessing = false;
  String postureMessage = "Loading...";
  List<List<double>>? referenceLandmarks;
  img.Image? referenceImage;

  Timer? periodicTimer;
  Timer? _goodPostureTimer; // New timer for the 6-second delay
  bool _isGoodPostureDetected = false; // New flag to track good posture state

  CameraImage? latestImage;

  @override
  void initState() {
    super.initState();
    initCamera();
    loadModel();
    extractReferencePose();

    periodicTimer = Timer.periodic(const Duration(seconds: 1), (_) async { // Changed to 1 second for more responsive check
      if (latestImage != null && referenceLandmarks != null && !isProcessing && !_isGoodPostureDetected) {
        isProcessing = true;
        final result = await computePoseDetection(
            latestImage!, interpreter, referenceLandmarks!);

        if (mounted) { // Check if the widget is still mounted before setState
          if (result) {
            // Good posture detected, start the 6-second timer
            setState(() {
              _isGoodPostureDetected = true;
              postureMessage = "✅ GOOD POSTURE";
            });
            _startGoodPostureTimer();
          } else {
            // Posture not good
            setState(() {
              postureMessage = "❌ ADJUST YOUR POSTURE";
            });
          }
          isProcessing = false;
        } else {
          isProcessing = false; // Ensure processing flag is reset even if unmounted
        }
      }
    });
  }

  void _startGoodPostureTimer() {
    _goodPostureTimer?.cancel(); // Cancel any existing timer
    _goodPostureTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        widget.onPoseMatched(); // Go to next step after 6 seconds
        setState(() {
          _isGoodPostureDetected = false; // Reset for the next pose
          postureMessage = "Loading..."; // Reset message
        });
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    interpreter.close();
    periodicTimer?.cancel();
    _goodPostureTimer?.cancel(); // Cancel the new timer
    super.dispose();
  }

  void initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      controller = CameraController(cameras[0], ResolutionPreset.medium);
      await controller.initialize();

      if (controller.value.isInitialized) {
        controller.startImageStream((CameraImage image) {
          latestImage = image;
        });
      }
    } else {
      print("No cameras available on this device.");
      if (mounted) {
        setState(() {
          postureMessage = "No camera available.";
        });
      }
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> loadModel() async {
    try {
      interpreter =
      await Interpreter.fromAsset('assets/models/movenet_lightning.tflite');
    } catch (e) {
      print('Error loading model: $e');
      if (mounted) {
        setState(() {
          postureMessage = "Error loading AI model.";
        });
      }
    }
  }

  Future<void> extractReferencePose() async {
    try {
      final byteData = await rootBundle.load(widget.referenceImagePath);
      final img.Image imgRef = img.decodeImage(byteData.buffer.asUint8List())!;
      final resized = img.copyResize(imgRef, width: 192, height: 192);

      if (mounted) {
        setState(() {
          referenceImage = resized;
        });
      }

      final input = List.generate(
        1,
            (_) =>
            List.generate(
              192,
                  (_) =>
                  List.generate(
                    192,
                        (_) => List.filled(3, 0),
                  ),
            ),
      );

      for (int y = 0; y < 192; y++) {
        for (int x = 0; x < 192; x++) {
          final pixel = resized.getPixel(x, y);
          input[0][y][x][0] = img.getRed(pixel);
          input[0][y][x][1] = img.getGreen(pixel);
          input[0][y][x][2] = img.getBlue(pixel);
        }
      }

      final output = List.filled(1 * 1 * 17 * 3, 0.0).reshape([1, 1, 17, 3]);
      interpreter.run(input, output);
      referenceLandmarks = output[0][0];
    } catch (e) {
      print('Error extracting reference pose: $e');
      if (mounted) {
        setState(() {
          postureMessage = "Error loading reference pose.";
        });
      }
    }
  }

  static Future<bool> computePoseDetection(CameraImage image,
      Interpreter interpreter, List<List<double>> referenceLandmarks) async {
    final imgBytes = _convertCameraImageStatic(image);
    final cameraImage = img.Image.fromBytes(
      image.width,
      image.height,
      imgBytes,
      format: img.Format.rgb,
    );
    final resized = img.copyResize(cameraImage, width: 192, height: 192);

    final input = List.generate(
      1,
          (_) =>
          List.generate(
            192,
                (_) =>
                List.generate(
                  192,
                      (_) => List.filled(3, 0),
                ),
          ),
    );

    for (int y = 0; y < 192; y++) {
      for (int x = 0; x < 192; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x][0] = img.getRed(pixel);
        input[0][y][x][1] = img.getGreen(pixel);
        input[0][y][x][2] = img.getBlue(pixel);
      }
    }

    final output = List.filled(1 * 1 * 17 * 3, 0.0).reshape([1, 1, 17, 3]);
    interpreter.run(input, output);

    final detected = output[0][0];

    double totalDiff = 0.0;
    for (int i = 0; i < detected.length; i++) {
      final dx = detected[i][0] - referenceLandmarks[i][0];
      final dy = detected[i][1] - referenceLandmarks[i][1];
      totalDiff += sqrt(dx * dx + dy * dy);
    }

    return totalDiff < 3.0; // Threshold (you increased it to 3.0, keeping it as is)
  }

  static Uint8List _convertCameraImageStatic(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    final imgBytes = Uint8List(width * height * 3);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);

        final int index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];

        int r = (yp + 1.403 * (vp - 128)).round();
        int g = (yp - 0.344 * (up - 128) - 0.714 * (vp - 128)).round();
        int b = (yp + 1.770 * (up - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        imgBytes[index * 3] = r;
        imgBytes[index * 3 + 1] = g;
        imgBytes[index * 3 + 2] = b;
      }
    }

    return imgBytes;
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final double cameraAspectRatio = controller.value.aspectRatio;

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            color: Colors.black12,
            child: referenceImage != null
                ? Image.memory(
              Uint8List.fromList(img.encodeJpg(referenceImage!)),
              fit: BoxFit.contain,
            )
                : const Center(child: Text("Loading Reference...")),
          ),
        ),
        Expanded(
          flex: 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: AspectRatio(
                  aspectRatio: cameraAspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    postureMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}