import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../services/ekyc_session.dart';
import '../services/ocr_service.dart';

class OcrCameraScreen extends StatefulWidget {
  const OcrCameraScreen({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<OcrCameraScreen> createState() => _OcrCameraScreenState();
}

class _OcrCameraScreenState extends State<OcrCameraScreen>
    with SingleTickerProviderStateMixin {
  final OcrService _ocrService = OcrService();
  final EkycSession _session = EkycSession.instance;

  CameraController? _cameraController;
  late final AnimationController _scanLineController;

  String? _errorMessage;
  bool _isInitialized = false;
  bool _isProcessingFrame = false;
  bool _isNavigating = false;
  bool _isTorchOn = false;
  DateTime _lastScanTime = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _scanDebounce = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  bool get _isMobileOcrPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _initializeCamera() async {
    if (!_isMobileOcrPlatform) {
      setState(() {
        _errorMessage = 'OCR realtime hiện chỉ hỗ trợ Android và iOS.';
      });
      return;
    }

    final permissionStatus = await Permission.camera.request();
    if (!permissionStatus.isGranted) {
      setState(() {
        _errorMessage =
            'Camera permission bị từ chối. Vui lòng cấp quyền để quét CCCD.';
      });
      return;
    }

    if (widget.cameras.isEmpty) {
      setState(() {
        _errorMessage = 'Không tìm thấy camera trên thiết bị.';
      });
      return;
    }

    final selectedCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: _isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await cameraController.initialize();
      await cameraController.startImageStream(_processCameraImage);

      if (!mounted) {
        await cameraController.dispose();
        return;
      }

      setState(() {
        _cameraController = cameraController;
        _isInitialized = true;
      });
    } catch (error) {
      await cameraController.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Không thể khởi tạo camera: $error';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final nextValue = !_isTorchOn;
    try {
      await controller.setFlashMode(
        nextValue ? FlashMode.torch : FlashMode.off,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isTorchOn = nextValue;
      });
    } catch (_) {
      _showMessage('Thiết bị không hỗ trợ đèn flash ở chế độ hiện tại.');
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessingFrame || _isNavigating || !mounted) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastScanTime) < _scanDebounce) {
      return;
    }
    _lastScanTime = now;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(
        cameraImage,
        controller.description,
      );
      if (inputImage == null) {
        return;
      }

      final ocrResult = await _ocrService.recognize(inputImage);
      if (!ocrResult.isComplete || !mounted) {
        return;
      }

      _isNavigating = true;

      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      if (!mounted) {
        return;
      }

      final normalizedCccd = ocrResult.cccd!.replaceAll(RegExp(r'\D'), '');
      final normalizedName = ocrResult.fullName!.trim().toUpperCase();
      final normalizedDob = ocrResult.dateOfBirth!.trim();

      _session.setOcrData(
        cccd: normalizedCccd,
        fullName: normalizedName,
        dateOfBirth: normalizedDob,
        cccdHash: OcrService.hashCccd(normalizedCccd),
      );

      await Navigator.of(context).pushNamed(AppRoutes.review);

      if (!mounted) {
        return;
      }

      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }

      _isNavigating = false;
    } catch (error) {
      debugPrint('OCR realtime error: $error');
      _isNavigating = false;

      final currentController = _cameraController;
      if (currentController != null &&
          currentController.value.isInitialized &&
          !currentController.value.isStreamingImages) {
        await currentController.startImageStream(_processCameraImage);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) {
      return null;
    }

    if (_isIOS) {
      if (image.planes.isEmpty) {
        return null;
      }

      final inputImageFormat = InputImageFormatValue.fromRawValue(
        image.format.raw,
      );
      if (inputImageFormat == null ||
          inputImageFormat != InputImageFormat.bgra8888) {
        return null;
      }

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (image.planes.length < 3) {
      return null;
    }

    // Android camera stream outputs YUV420. Convert to NV21 for ML Kit OCR.
    final nv21Bytes = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = ySize ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    var destIndex = 0;

    for (var row = 0; row < height; row++) {
      final rowOffset = row * yPlane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        nv21[destIndex++] = yPlane.bytes[rowOffset + col];
      }
    }

    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;
    final uBytesPerPixel = uPlane.bytesPerPixel ?? 1;
    final vBytesPerPixel = vPlane.bytesPerPixel ?? 1;

    for (var row = 0; row < chromaHeight; row++) {
      final uRowOffset = row * uPlane.bytesPerRow;
      final vRowOffset = row * vPlane.bytesPerRow;

      for (var col = 0; col < chromaWidth; col++) {
        final uIndex = uRowOffset + col * uBytesPerPixel;
        final vIndex = vRowOffset + col * vBytesPerPixel;

        nv21[destIndex++] = vPlane.bytes[vIndex];
        nv21[destIndex++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _scanLineController.dispose();

    final controller = _cameraController;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream();
      }
      controller.dispose();
    }

    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('OCR Camera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.welcome,
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Về màn hình chào'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.36),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.56),
                  ],
                  stops: const [0, 0.22, 0.68, 1],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _scanLineController,
            builder: (_, _) {
              final curvedProgress = AppMotion.gentle.transform(
                _scanLineController.value,
              );
              return _CardOverlay(scanProgress: curvedProgress);
            },
          ),
          Positioned(
            top: compact ? 22 : 56,
            left: pagePadding,
            right: pagePadding,
            child: Container(
              padding: EdgeInsets.all(compact ? 12 : 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.document_scanner, color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'OCR Core - CCCD',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleTorch,
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.24),
                        ),
                        icon: Icon(
                          _isTorchOn
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    switchInCurve: AppMotion.standard,
                    child: Text(
                      _isNavigating
                          ? 'Đã nhận diện thông tin. Đang mở màn hình kiểm tra...'
                          : 'Đặt CCCD vào khung. Hệ thống nhận diện dữ liệu ngay trên thiết bị.',
                      key: ValueKey<bool>(_isNavigating),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: pagePadding,
            right: pagePadding,
            bottom: compact ? 16 : 24,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: compact ? 9 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_isNavigating)
                          const Icon(Icons.verified, color: Colors.greenAccent)
                        else
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: AppMotion.fast,
                            child: Text(
                              _isNavigating
                                  ? 'Đang chuyển sang bước Review...'
                                  : 'Đang quét realtime...',
                              key: ValueKey<bool>(_isNavigating),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 9 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A3D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Privacy-First',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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

class _CardOverlay extends StatelessWidget {
  const _CardOverlay({required this.scanProgress});

  final double scanProgress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CardOverlayPainter(scanProgress: scanProgress),
        size: Size.infinite,
      ),
    );
  }
}

class _CardOverlayPainter extends CustomPainter {
  _CardOverlayPainter({required this.scanProgress});

  final double scanProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.88,
      height: size.height * 0.28,
    );

    final dimmedPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(overlayRect, const Radius.circular(16)),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      dimmedPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(overlayRect, const Radius.circular(16)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    final cornerPaint = Paint()
      ..color = const Color(0xFFFF8A3D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const corner = 34.0;

    canvas.drawLine(
      Offset(overlayRect.left, overlayRect.top + corner),
      Offset(overlayRect.left, overlayRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(overlayRect.left, overlayRect.top),
      Offset(overlayRect.left + corner, overlayRect.top),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(overlayRect.right - corner, overlayRect.top),
      Offset(overlayRect.right, overlayRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(overlayRect.right, overlayRect.top),
      Offset(overlayRect.right, overlayRect.top + corner),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(overlayRect.left, overlayRect.bottom - corner),
      Offset(overlayRect.left, overlayRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(overlayRect.left, overlayRect.bottom),
      Offset(overlayRect.left + corner, overlayRect.bottom),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(overlayRect.right - corner, overlayRect.bottom),
      Offset(overlayRect.right, overlayRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(overlayRect.right, overlayRect.bottom - corner),
      Offset(overlayRect.right, overlayRect.bottom),
      cornerPaint,
    );

    final scanY =
        overlayRect.top + 10 + ((overlayRect.height - 20) * scanProgress);
    final scanRect = Rect.fromLTRB(
      overlayRect.left + 10,
      scanY,
      overlayRect.right - 10,
      scanY + 1,
    );

    final scanPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x00FF8A3D), Color(0xFFFF8A3D), Color(0x00FF8A3D)],
      ).createShader(scanRect)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(overlayRect.left + 10, scanY),
      Offset(overlayRect.right - 10, scanY),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CardOverlayPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress;
  }
}
