import 'dart:async';
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
  bool _cameraReady = false;
  bool _modelReady = false;
  bool _completed = false;

  CameraImage? latestImage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await loadModel();
      if (!mounted || !_modelReady) return;
      await extractReferencePose();
      if (!mounted || referenceLandmarks == null) return;
      await initCamera();
      if (!mounted || !_cameraReady) return;
    } catch (_) {
      if (mounted)
        setState(() => postureMessage =
            'Unable to start pose matching. Check camera permission and reopen this guide.');
      return;
    }

    periodicTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      // Changed to 1 second for more responsive check
      if (latestImage != null &&
          referenceLandmarks != null &&
          !isProcessing &&
          !_completed) {
        isProcessing = true;
        try {
          final result = await computePoseDetection(
              latestImage!, interpreter, referenceLandmarks!);

          if (mounted) {
            // Check if the widget is still mounted before setState
            if (result && !_isGoodPostureDetected) {
              // Good posture detected, start the 6-second timer
              setState(() {
                _isGoodPostureDetected = true;
                postureMessage = "✅ GOOD POSTURE";
              });
              _startGoodPostureTimer();
            } else if (!result) {
              _goodPostureTimer?.cancel();
              _isGoodPostureDetected = false;
              // Posture not good
              setState(() {
                postureMessage = "❌ ADJUST YOUR POSTURE";
              });
            }
          }
        } catch (_) {
          _goodPostureTimer?.cancel();
          _isGoodPostureDetected = false;
          if (mounted)
            setState(() => postureMessage =
                'Move your whole body into view and try again.');
        } finally {
          isProcessing = false;
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant PoseMatchCameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.referenceImagePath != widget.referenceImagePath) {
      _goodPostureTimer?.cancel();
      _isGoodPostureDetected = false;
      _completed = false;
      referenceLandmarks = null;
      if (_modelReady) extractReferencePose();
    }
  }

  void _startGoodPostureTimer() {
    _goodPostureTimer?.cancel(); // Cancel any existing timer
    _goodPostureTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        _completed = true;
        widget.onPoseMatched(); // Go to next step after 6 seconds
      }
    });
  }

  @override
  void dispose() {
    periodicTimer?.cancel();
    _goodPostureTimer?.cancel(); // Cancel the new timer
    if (_cameraReady) controller.dispose();
    if (_modelReady) interpreter.close();
    super.dispose();
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    if (!mounted) return;
    if (cameras.isNotEmpty) {
      controller = CameraController(cameras[0], ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _cameraReady = true;

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
      if (!mounted) {
        interpreter.close();
        return;
      }
      _modelReady = true;
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
    final referencePath = widget.referenceImagePath;
    try {
      final byteData = await rootBundle.load(referencePath);
      if (!mounted || referencePath != widget.referenceImagePath) return;
      final img.Image imgRef = img.decodeImage(byteData.buffer.asUint8List())!;
      final resized = img.copyResize(imgRef, width: 192, height: 192);

      if (mounted) {
        setState(() {
          referenceImage = resized;
        });
      }

      final input = List.generate(
        1,
        (_) => List.generate(
          192,
          (_) => List.generate(
            192,
            (_) => List.filled(3, 0),
          ),
        ),
      );

      for (int y = 0; y < 192; y++) {
        for (int x = 0; x < 192; x++) {
          final pixel = resized.getPixel(x, y);
          input[0][y][x][0] = pixel.r.toInt();
          input[0][y][x][1] = pixel.g.toInt();
          input[0][y][x][2] = pixel.b.toInt();
        }
      }

      final output = List.filled(1 * 1 * 17 * 3, 0.0).reshape([1, 1, 17, 3]);
      interpreter.run(input, output);
      referenceLandmarks = [
        for (final point in output[0][0])
          [for (final value in point) (value as num).toDouble()]
      ];
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
        width: image.width,
        height: image.height,
        bytes: imgBytes.buffer,
        numChannels: 3);
    final resized = img.copyResize(cameraImage, width: 192, height: 192);

    final input = List.generate(
      1,
      (_) => List.generate(
        192,
        (_) => List.generate(
          192,
          (_) => List.filled(3, 0),
        ),
      ),
    );

    for (int y = 0; y < 192; y++) {
      for (int x = 0; x < 192; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x][0] = pixel.r.toInt();
        input[0][y][x][1] = pixel.g.toInt();
        input[0][y][x][2] = pixel.b.toInt();
      }
    }

    final output = List.filled(1 * 1 * 17 * 3, 0.0).reshape([1, 1, 17, 3]);
    interpreter.run(input, output);

    final detected = output[0][0];

    double totalDiff = 0.0;
    int visiblePoints = 0;
    for (int i = 0; i < detected.length; i++) {
      if (detected[i][2] < .2 || referenceLandmarks[i][2] < .2) continue;
      visiblePoints++;
      final dx = detected[i][0] - referenceLandmarks[i][0];
      final dy = detected[i][1] - referenceLandmarks[i][1];
      totalDiff += sqrt(dx * dx + dy * dy);
    }

    return visiblePoints >= 6 && totalDiff / visiblePoints < .18;
  }

  static Uint8List _convertCameraImageStatic(CameraImage image) {
    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      throw StateError('Pose matching requires a YUV420 camera stream.');
    }
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final imgBytes = Uint8List(width * height * 3);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);

        final int index = y * width + x;

        final yp = image.planes[0].bytes[y * image.planes[0].bytesPerRow + x];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[
            (y ~/ 2) * image.planes[2].bytesPerRow +
                (x ~/ 2) * (image.planes[2].bytesPerPixel ?? 1)];

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
    if (!_cameraReady || !controller.value.isInitialized) {
      return Center(child: Text(postureMessage, textAlign: TextAlign.center));
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
