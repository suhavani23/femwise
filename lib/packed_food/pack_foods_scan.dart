import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:femwise/services/ingredient_service.dart';

class ImageToTextScreen extends StatefulWidget {
  const ImageToTextScreen({super.key});
  @override
  State<ImageToTextScreen> createState() => _ImageToTextScreenState();
}

class _ImageToTextScreenState extends State<ImageToTextScreen>
    with WidgetsBindingObserver {
  final _service = IngredientService();
  CameraController? _camera;
  bool _startingCamera = false;
  bool _isProcessing = false;
  String _cameraMessage = 'Starting camera…';
  String _extractedText = '';
  String _review = '';
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_startingCamera || _camera != null) return;
    _startingCamera = true;
    final generation = ++_cameraGeneration;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted || generation != _cameraGeneration) return;
      if (cameras.isEmpty)
        throw CameraException('NoCamera', 'No camera found.');
      final selected = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      controller =
          CameraController(selected, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
      });
    } catch (_) {
      await controller?.dispose();
      if (mounted)
        setState(() {
          _cameraMessage =
              'Camera unavailable. You can choose a photo or enter ingredients below.';
        });
    } finally {
      _startingCamera = false;
      if (mounted &&
          generation != _cameraGeneration &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _initializeCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraGeneration++;
      final controller = _camera;
      _camera = null;
      controller?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _analyze(String text) async {
    if (!mounted) return;
    setState(() {
      _extractedText = text;
      _review = '';
      _isProcessing = true;
    });
    try {
      final review = await _service.analyze(text);
      if (mounted) setState(() => _review = review);
    } catch (error) {
      if (mounted) setState(() => _review = error.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _editIngredients() async {
    final controller = TextEditingController(text: _extractedText);
    final route = DialogRoute<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Enter ingredients'),
              content: SingleChildScrollView(
                  child: TextField(
                controller: controller,
                minLines: 3,
                maxLines: 8,
                maxLength: 20000,
                decoration: const InputDecoration(
                    hintText: 'Paste or type the ingredient list'),
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty)
                        Navigator.pop(dialogContext, controller.text.trim());
                    },
                    child: const Text('Analyze')),
              ],
            ));
    final text = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (text != null && mounted) await _analyze(text);
  }

  Future<void> _scan({required bool gallery}) async {
    setState(() => _isProcessing = true);
    try {
      final XFile? photo = gallery
          ? await ImagePicker().pickImage(source: ImageSource.gallery)
          : await _camera?.takePicture();
      if (photo == null || !mounted) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: photo.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
              toolbarTitle: 'Crop ingredient list',
              toolbarColor: Colors.deepPurple,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: false),
          IOSUiSettings(title: 'Crop ingredient list')
        ],
      );
      if (cropped == null || !mounted) return;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer
            .processImage(InputImage.fromFilePath(cropped.path));
        if (!mounted) return;
        if (result.text.trim().isEmpty) {
          setState(() => _review =
              'No text was found. Try a clearer photo or enter ingredients.');
        } else {
          await _analyze(result.text);
        }
      } finally {
        await recognizer.close();
      }
    } catch (_) {
      if (mounted)
        setState(() => _review =
            'Unable to read this image. Please retry or enter ingredients.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Ingredients Scanner'),
            backgroundColor: Colors.deepPurple.shade400,
            foregroundColor: Colors.white),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: _camera?.value.isInitialized == true
                  ? ClipRect(child: Center(child: CameraPreview(_camera!)))
                  : Center(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_cameraMessage,
                              textAlign: TextAlign.center)))),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                  'Ingredient text is sent for AI review. Your tracking records stay on this phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12))),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            IconButton(
                tooltip: 'Scan with camera',
                icon: const Icon(Icons.camera_alt),
                onPressed: _isProcessing || _camera?.value.isInitialized != true
                    ? null
                    : () => _scan(gallery: false)),
            IconButton(
                tooltip: 'Choose label photo',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _isProcessing ? null : () => _scan(gallery: true)),
            TextButton.icon(
                onPressed: _isProcessing ? null : _editIngredients,
                icon: const Icon(Icons.edit_note),
                label: const Text('Enter / edit ingredients')),
          ]),
          Expanded(
              child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: _isProcessing
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Reading ingredients…')
                  ]))
                : SingleChildScrollView(
                    child: SelectableText(
                        [
                          _extractedText.isEmpty
                              ? 'Scan a label, choose a photo or enter ingredients.'
                              : 'Scanned text:\n$_extractedText',
                          if (_review.isNotEmpty) _review
                        ].join('\n\n'),
                        style: GoogleFonts.montserrat(fontSize: 15))),
          )),
        ])),
      );
}
