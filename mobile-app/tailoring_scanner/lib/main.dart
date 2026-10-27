import 'dart:io';

import 'pdf_generator.dart';
import 'history_screen.dart';

import 'package:http/http.dart' as http;
import 'package:ditredi/ditredi.dart';

import 'dart:convert';

import 'database_helper.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

// Set with --dart-define=API_BASE_URL=http://<computer-ip>:8000 when building
// for a phone. Both measurement uploads and model downloads must use the same
// backend on the local network.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.82.229.227:8000',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.camera.request();
  cameras = await availableCameras();
  runApp(const TailoringApp());
}

class TailoringApp extends StatelessWidget {
  const TailoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Tailor Scanner',
      theme: ThemeData.dark(),
      home: const InstructionsScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  final ImagePicker _picker = ImagePicker();

  int _step = 1; // Step 1: Calibration (A4 paper), Step 2: Body pose
  String? _calibImagePath;
  String? _bodyImagePath;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    _controller = CameraController(
      backCamera,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller.initialize();
    if (mounted) setState(() => _isCameraInitialized = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleImageSelected(String path) {
    if (_step == 1) {
      setState(() {
        _calibImagePath = path;
        _step = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Step 1 captured! Now stand relaxed with arms at your sides.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      _bodyImagePath = path;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DualPreviewScreen(
            calibImagePath: _calibImagePath!,
            bodyImagePath: _bodyImagePath!,
            onReset: () {
              Navigator.pop(context);
              setState(() {
                _step = 1;
                _calibImagePath = null;
                _bodyImagePath = null;
              });
            },
          ),
        ),
      );
    }
  }

  Future<void> _captureImage() async {
    if (!_controller.value.isInitialized || _controller.value.isTakingPicture)
      return;
    try {
      final XFile imageFile = await _controller.takePicture();
      _handleImageSelected(imageFile.path);
    } catch (e) {
      print("Capture error: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? imageFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (imageFile != null) {
        _handleImageSelected(imageFile.path);
      }
    } catch (e) {
      print("Gallery error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepText = _step == 1
        ? "STEP 1: Hold A4 Paper flat at chest"
        : "STEP 2: Stand relaxed, arms at sides";
    final stepColor = _step == 1 ? Colors.amberAccent : Colors.lightGreenAccent;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraInitialized
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                CustomPaint(painter: SilhouettePainter()),

                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: stepColor, width: 1.5),
                    ),
                    child: Text(
                      stepText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: stepColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton(
                        heroTag: 'gallery_btn',
                        onPressed: _pickFromGallery,
                        backgroundColor: Colors.grey[850],
                        child: const Icon(
                          Icons.photo_library,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'camera_btn',
                        onPressed: _captureImage,
                        backgroundColor: Colors.white,
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.black,
                          size: 36,
                        ),
                      ),
                      if (_step == 2)
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Colors.white,
                            size: 30,
                          ),
                          tooltip: 'Restart from Step 1',
                          onPressed: () => setState(() {
                            _step = 1;
                            _calibImagePath = null;
                            _bodyImagePath = null;
                          }),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final boundaryPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Outer framing box (shows the optimal capture zone)
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY - 20),
        width: size.width * 0.72,
        height: size.height * 0.78,
      ),
      const Radius.circular(16),
    );
    canvas.drawRRect(frameRect, boundaryPaint);

    // 1. Head Guide (Scaled for ~2.5 - 3m distance)
    final headRect = Rect.fromCenter(
      center: Offset(centerX, centerY - 180),
      width: 44,
      height: 60,
    );
    canvas.drawOval(headRect, guidePaint);

    // 2. Torso & Arms Guide
    final bodyPath = Path();
    bodyPath.moveTo(centerX - 22, centerY - 150);
    bodyPath.quadraticBezierTo(
      centerX - 65,
      centerY - 145,
      centerX - 70,
      centerY - 95,
    );
    bodyPath.lineTo(centerX - 70, centerY + 60);

    bodyPath.moveTo(centerX + 22, centerY - 150);
    bodyPath.quadraticBezierTo(
      centerX + 65,
      centerY - 145,
      centerX + 70,
      centerY - 95,
    );
    bodyPath.lineTo(centerX + 70, centerY + 60);
    canvas.drawPath(bodyPath, guidePaint);

    // 3. Legs Guide
    final legPath = Path();
    // Left leg
    legPath.moveTo(centerX - 35, centerY + 60);
    legPath.lineTo(centerX - 30, centerY + 210);
    // Right leg
    legPath.moveTo(centerX + 35, centerY + 60);
    legPath.lineTo(centerX + 30, centerY + 210);
    canvas.drawPath(legPath, guidePaint);

    // 4. Baseline (Ground level marker)
    final floorPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(centerX - 60, centerY + 215),
      Offset(centerX + 60, centerY + 215),
      floorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DualPreviewScreen extends StatefulWidget {
  final String calibImagePath;
  final String bodyImagePath;
  final VoidCallback onReset;

  const DualPreviewScreen({
    super.key,
    required this.calibImagePath,
    required this.bodyImagePath,
    required this.onReset,
  });

  @override
  State<DualPreviewScreen> createState() => _DualPreviewScreenState();
}

class _DualPreviewScreenState extends State<DualPreviewScreen> {
  bool _isUploading = false;
  bool _showHeightInput = false;
  final TextEditingController _heightController = TextEditingController();

  Future<void> _uploadImages() async {
    setState(() => _isUploading = true);

    try {
      var uri = Uri.parse('$apiBaseUrl/upload');
      var request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath('body_image', widget.bodyImagePath),
      );
      request.files.add(
        await http.MultipartFile.fromPath('calib_image', widget.calibImagePath),
      );

      if (_showHeightInput && _heightController.text.isNotEmpty) {
        request.fields['height_cm'] = _heightController.text;
      }
      // 1. Send the multipart request
      final streamedResponse = await request.send();

      // 2. Convert the stream into a reusable Response object immediately
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      // 3. Now you can safely use response.body as a String multiple times
      print("SERVER RESPONSE: ${response.body}");

      try {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (response.statusCode == 200) {
          // Persist analytics separately from the measurement request. A
          // dashboard/database outage must not prevent a successful scan.
          try {
            await http.post(
              Uri.parse('$apiBaseUrl/api/scans'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'customer_name': 'Walk-in customer',
                'recommended_size':
                    data['sizing']?['recommended_size'] ?? 'Unknown',
                'fit_preference': data['sizing']?['fit_type'] ?? 'Regular Fit',
              }),
            );
          } catch (analyticsError) {
            print(
              'Analytics save failed; continuing to results: $analyticsError',
            );
          }
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ResultsScreen(
                  measurements: data['measurements'],
                  scanId: data['scan_id'],
                  sizing: data['sizing'] == null
                      ? null
                      : Map<String, dynamic>.from(data['sizing']),
                ),
              ),
            );
          }
        } else if (response.statusCode == 400 &&
            data['error'] == "A4_FAILED_NEED_HEIGHT") {
          setState(() => _showHeightInput = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A4 Paper missed in Step 1. Enter height to continue.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: ${data['error']}')));
        }
      } catch (e) {
        print("JSON PARSE ERROR: $e");
      }
    } catch (e) {
      print("Upload error: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Review Both Captures'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.onReset,
            tooltip: 'Retake Both',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. The Background Images
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Text(
                              "Step 1 (Scale)",
                              style: TextStyle(color: Colors.amberAccent),
                            ),
                          ),
                          Expanded(
                            child: Image.file(
                              File(widget.calibImagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 2, color: Colors.grey),
                    Expanded(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Text(
                              "Step 2 (Body)",
                              style: TextStyle(color: Colors.lightGreenAccent),
                            ),
                          ),
                          Expanded(
                            child: Image.file(
                              File(widget.bodyImagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),

          // 2. The Height Input Fallback
          if (_showHeightInput && !_isUploading)
            Positioned(
              bottom: 90,
              left: 30,
              right: 30,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _heightController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Paper missed. Enter Height (cm)",
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),

          // 3. The Professional Loading Overlay
          if (_isUploading) const _ProcessingOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _uploadImages,
        icon: const Icon(Icons.straighten),
        backgroundColor: _isUploading ? Colors.grey : Colors.deepPurpleAccent,
        label: Text(
          _showHeightInput ? "Recalculate with Height" : "Scan AI Measurements",
        ),
      ),
    );
  }
}

class ResultsScreen extends StatefulWidget {
  final Map<String, dynamic> measurements;
  final String? scanId;
  final Map<String, dynamic>? sizing;
  final String? calibImagePath; // <--- Added '?' to make it optional

  const ResultsScreen({
    super.key,
    required this.measurements,
    this.scanId,
    this.sizing,
    this.calibImagePath, // <--- Removed 'required'
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _show3D = false;
  String _selectedFit = 'Slim Fit';
  double get _dynamicScaleX {
    double baseWidth = widget.measurements['shoulder_width']?['cm'] ?? 40.0;
    double scale = baseWidth / 40.0;

    // Morph the avatar width based on clothing fit preference
    if (_selectedFit == 'Loose Fit') scale *= 1.15;
    if (_selectedFit == 'Regular Fit') scale *= 1.05;

    return scale.clamp(0.7, 1.4); // Clamp to prevent extreme distortion
  }

  // Calculates height ratio using combined torso and leg length against a 115cm baseline
  double get _dynamicScaleY {
    double torso = widget.measurements['torso_length']?['cm'] ?? 45.0;
    double legs = widget.measurements['leg_length']?['cm'] ?? 70.0;
    double scale = (torso + legs) / 115.0;

    return scale.clamp(0.7, 1.4);
  }

  Mesh3D? _mesh3D; // Native 3D object
  DiTreDiController? _ditrediController; // Handles native rotation

  String? _modelError;

  @override
  void initState() {
    super.initState();
    if (widget.scanId != null) {
      _fetchAndParseObj();
    }
  }

  // Natively downloads and parses the .obj math without saving to storage
  Future<void> _fetchAndParseObj() async {
    try {
      final url = '$apiBaseUrl/model-3d/${widget.scanId}.obj';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final faces = await ObjParser().parse(response.body);
        if (mounted) {
          setState(() {
            _mesh3D = Mesh3D(faces);
            _ditrediController = DiTreDiController();
          });
        }
      } else if (mounted) {
        setState(
          () => _modelError =
              'Model unavailable (${response.statusCode}). Check that the phone can reach the backend.',
        );
      }
    } catch (e) {
      print("Fetch error: $e");
      if (mounted)
        setState(() => _modelError = 'Could not reach the measurement server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Measurements"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // HISTORY ICON
          // PDF EXPORT BUTTON
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: () async {
              await PdfGenerator.generateAndSharePdf(
                measurements: widget.measurements,
                sizing: widget.sizing,
                imagePath: widget.calibImagePath,
                scanId: widget.scanId ?? 'Unknown',
              );
            },
          ),
          // SAVE ICON
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
            onPressed: () async {
              final scanData = {
                'scan_id': widget.scanId ?? 'Unknown',
                'recommended_size': widget.sizing != null
                    ? widget.sizing!['recommended_size']
                    : 'N/A',
                'image_path': widget.calibImagePath ?? 'No Image',
                'measurements_json': jsonEncode(widget.measurements),
                'created_at': DateTime.now().toIso8601String(),
              };

              await DatabaseHelper.instance.insertScan(scanData);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Measurements securely saved!",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // --- 2D / 3D TOGGLE ---
            // --- 2D / 3D TOGGLE ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "2D Diagram",
                  style: TextStyle(color: Colors.white70),
                ),
                Switch(
                  value: _show3D,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (val) => setState(() => _show3D = val),
                ),
                const Text(
                  "3D Avatar",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- NEW: FIT PREFERENCE TOGGLE ---
            if (_show3D) ...[
              Center(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'Slim Fit',
                      label: Text('Slim', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: 'Regular Fit',
                      label: Text('Regular', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: 'Loose Fit',
                      label: Text('Loose', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_selectedFit},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _selectedFit = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color>((
                      states,
                    ) {
                      return states.contains(WidgetState.selected)
                          ? Colors.deepPurpleAccent
                          : const Color(0xFF2C2C2C);
                    }),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // --- 3D VIEWER / 2D DIAGRAM CONTAINER ---
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 350,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: _show3D
                  ? (widget.scanId != null
                        ? (_mesh3D == null
                              ? (_modelError != null
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.wifi_off,
                                              color: Colors.white54,
                                            ),
                                            const SizedBox(height: 8),
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                _modelError!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                setState(
                                                  () => _modelError = null,
                                                );
                                                _fetchAndParseObj();
                                              },
                                              child: const Text('Retry'),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            color: Colors.deepPurpleAccent,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            "Compiling Native 3D Mesh...",
                                            style: TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  // NEW: Parametric Avatar Scaling
                                  child: Transform(
                                    transform: Matrix4.identity()
                                      ..scale(
                                        _dynamicScaleX,
                                        _dynamicScaleY,
                                        1.0,
                                      ),
                                    alignment: Alignment.center,
                                    child: DiTreDiDraggable(
                                      controller: _ditrediController!,
                                      child: DiTreDi(
                                        figures: [_mesh3D!],
                                        controller: _ditrediController,
                                      ),
                                    ),
                                  ),
                                ))
                        : const Center(
                            child: Text(
                              "No 3D Model Available",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ))
                  : (widget.calibImagePath != null
                        ? CustomPaint(
                            painter: BodyDiagramPainter(),
                            size: Size.infinite,
                          )
                        : const Center(
                            child: Icon(
                              Icons.accessibility_new,
                              size: 120,
                              color: Colors.white24,
                            ),
                          )),
            ),
            const SizedBox(height: 16),

            // --- SIZING RECOMMENDATION BADGE ---
            if (widget.sizing != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.deepPurpleAccent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.deepPurpleAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Recommended Size: ${widget.sizing!['recommended_size']}",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.sizing!['fit_type'],
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.deepPurpleAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.sizing!['fit_notes']['shoulder'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),

            // --- MEASUREMENTS LIST ---
            // --- MEASUREMENTS LIST ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.measurements.length,
                itemBuilder: (context, index) {
                  String key = widget.measurements.keys.elementAt(index);
                  var data = widget.measurements[key];

                  // BULLETPROOF FIX: If the data isn't a dictionary (like the 22.71 number), skip it entirely!
                  if (data == null || data is! Map)
                    return const SizedBox.shrink();

                  String formattedTitle = key
                      .replaceAll('_', ' ')
                      .split(' ')
                      .map((str) => str[0].toUpperCase() + str.substring(1))
                      .join(' ');

                  IconData rowIcon = Icons.straighten;
                  Color iconColor = Colors.blueAccent;
                  if (key.contains('sleeve')) {
                    rowIcon = Icons.back_hand;
                    iconColor = Colors.greenAccent;
                  } else if (key.contains('torso') || key.contains('leg')) {
                    rowIcon = Icons.accessibility_new;
                    iconColor = Colors.purpleAccent;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(rowIcon, color: iconColor),
                            const SizedBox(width: 16),
                            Text(
                              formattedTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${data['cm']} cm",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            Text(
                              "${data['in']} in",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// Visual Diagram Painter for the Top Section
class BodyDiagramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 1. Draw minimal mannequin outline
    // Head
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, centerY - 90),
        width: 30,
        height: 40,
      ),
      bodyPaint,
    );
    // Torso/Shoulders
    final bodyPath = Path();
    bodyPath.moveTo(centerX - 15, centerY - 70);
    bodyPath.quadraticBezierTo(
      centerX - 40,
      centerY - 65,
      centerX - 45,
      centerY - 30,
    );
    bodyPath.lineTo(centerX - 45, centerY + 30); // Left arm
    bodyPath.moveTo(centerX + 15, centerY - 70);
    bodyPath.quadraticBezierTo(
      centerX + 40,
      centerY - 65,
      centerX + 45,
      centerY - 30,
    );
    bodyPath.lineTo(centerX + 45, centerY + 30); // Right arm
    // Hips/Legs
    bodyPath.moveTo(centerX - 25, centerY + 20);
    bodyPath.lineTo(centerX - 25, centerY + 100);
    bodyPath.moveTo(centerX + 25, centerY + 20);
    bodyPath.lineTo(centerX + 25, centerY + 100);
    canvas.drawPath(bodyPath, bodyPaint);

    // 2. Draw Measurement Highlight Lines
    void drawMeasurementMarker(Offset start, Offset end, Color color) {
      linePaint.color = color;
      canvas.drawLine(start, end, linePaint);
      canvas.drawCircle(start, 4, dotPaint);
      canvas.drawCircle(end, 4, dotPaint);
    }

    // Shoulders (Blue)
    drawMeasurementMarker(
      Offset(centerX - 35, centerY - 60),
      Offset(centerX + 35, centerY - 60),
      Colors.blueAccent,
    );
    // Torso (Purple)
    drawMeasurementMarker(
      Offset(centerX, centerY - 55),
      Offset(centerX, centerY + 20),
      Colors.purpleAccent,
    );
    // Sleeve (Green - Left Arm)
    drawMeasurementMarker(
      Offset(centerX - 40, centerY - 60),
      Offset(centerX - 45, centerY + 35),
      Colors.greenAccent,
    );
    // Hips (Orange)
    drawMeasurementMarker(
      Offset(centerX - 25, centerY + 25),
      Offset(centerX + 25, centerY + 25),
      Colors.orangeAccent,
    );
    // Leg Outseam (Red - Right Leg)
    drawMeasurementMarker(
      Offset(centerX + 25, centerY + 25),
      Offset(centerX + 25, centerY + 105),
      Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('How to Scan'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  const Text(
                    "Get the Perfect Fit",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Follow these 4 rules for AI precision.",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),

                  _buildRuleCard(
                    icon: Icons.checkroom,
                    color: Colors.blueAccent,
                    title: "1. Wear Dark, Fitted Clothes",
                    description: "Avoid white or baggy shirts. The AI needs contrast to detect the white A4 paper.",
                  ),
                  _buildRuleCard(
                    icon: Icons.description,
                    color: Colors.amberAccent,
                    title: "2. Use Standard A4 Paper",
                    description: "Hold a standard white A4 sheet perfectly flat against your chest for Step 1.",
                  ),
                  _buildRuleCard(
                    icon: Icons.smartphone,
                    color: Colors.greenAccent,
                    title: "3. Prop the Phone Up",
                    description: "Place your phone on a table or shelf at chest height. Do not tilt it up or down.",
                  ),
                  _buildRuleCard(
                    icon: Icons.straighten,
                    color: Colors.purpleAccent,
                    title: "4. Step Back 3 Meters",
                    description: "Stand far enough back so your entire body fits inside the green screen guide.",
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: const BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CameraScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "I Understand, Open Camera",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingOverlay extends StatefulWidget {
  const _ProcessingOverlay();

  @override
  State<_ProcessingOverlay> createState() => _ProcessingOverlayState();
}

class _ProcessingOverlayState extends State<_ProcessingOverlay> {
  int _step = 0;
  final List<String> _stages = [
    "Detecting calibration reference...",
    "Extracting MediaPipe body contours...",
    "Calculating millimeter dimensions...",
    "Generating 3D sizing parameters...",
  ];

  @override
  void initState() {
    super.initState();
    _cycleMessages();
  }

  void _cycleMessages() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) {
        setState(() {
          _step = (_step + 1) % _stages.length;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Colors.deepPurpleAccent,
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _stages[_step],
                key: ValueKey<int>(_step),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
