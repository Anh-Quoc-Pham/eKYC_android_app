import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../models/decision_models.dart';
import '../services/ekyc_session.dart';
import '../services/ocr_service.dart';

enum OcrPermissionUiState { preAsk, denied, permanentlyDenied }

class OcrCameraScreen extends StatefulWidget {
  const OcrCameraScreen({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<OcrCameraScreen> createState() => _OcrCameraScreenState();
}

class _OcrCameraScreenState extends State<OcrCameraScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OcrService _ocrService = OcrService();
  final EkycSession _session = EkycSession.instance;

  CameraController? _cameraController;
  late final AnimationController _scanLineController;

  OcrPermissionUiState _permissionUiState = OcrPermissionUiState.preAsk;
  String? _fatalError;
  bool _isInitialized = false;
  bool _isPreparingCamera = false;
  bool _isRequestingPermission = false;
  bool _isProcessingFrame = false;
  bool _isNavigating = false;
  bool _isTorchOn = false;
  DateTime _lastScanTime = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _hintTimer;
  int _hintIndex = 0;

  static const Duration _scanDebounce = Duration(milliseconds: 450);
  static const List<String> _helperHints = <String>[
    'Tránh bị lóa',
    'Giữ điện thoại thẳng',
    'Đưa lại gần hơn một chút',
    'Giữ yên trong giây lát',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _hintTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isNavigating || !_isInitialized) {
        return;
      }
      setState(() {
        _hintIndex = (_hintIndex + 1) % _helperHints.length;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _isInitialized) {
      return;
    }
    if (_permissionUiState == OcrPermissionUiState.preAsk) {
      return;
    }
    _checkPermissionAfterSettings();
  }

  bool get _isMobileOcrPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _checkPermissionAfterSettings() async {
    final status = await Permission.camera.status;
    if (!mounted || !status.isGranted) {
      return;
    }
    await _prepareCamera();
  }

  Future<void> _requestCameraPermission() async {
    if (_isRequestingPermission) {
      return;
    }
    setState(() {
      _isRequestingPermission = true;
    });

    try {
      final permissionStatus = await Permission.camera.request();

      if (!mounted) {
        return;
      }

      if (permissionStatus.isGranted) {
        await _prepareCamera();
        return;
      }

      setState(() {
        _permissionUiState = permissionStatus.isPermanentlyDenied
            ? OcrPermissionUiState.permanentlyDenied
            : OcrPermissionUiState.denied;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermission = false;
        });
      }
    }
  }

  Future<void> _prepareCamera() async {
    if (_isPreparingCamera || _isInitialized) {
      return;
    }

    if (!_isMobileOcrPlatform) {
      setState(() {
        _fatalError = 'Thiết bị này chưa hỗ trợ chụp giấy tờ bằng camera.';
      });
      return;
    }

    if (widget.cameras.isEmpty) {
      setState(() {
        _fatalError = 'Không tìm thấy camera trên thiết bị này.';
      });
      return;
    }

    setState(() {
      _isPreparingCamera = true;
      _fatalError = null;
    });

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
        _isPreparingCamera = false;
      });
    } catch (error) {
      await cameraController.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _isPreparingCamera = false;
        _fatalError = 'Không thể bật camera. Vui lòng thử lại.';
      });
      debugPrint('Không thể khởi tạo camera OCR: $error');
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
      _showMessage('Thiết bị không hỗ trợ đèn flash ở chế độ này.');
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
        ocrRiskSignals: const OcrRiskSignals(confidence: 0.92),
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
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
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

    if (_fatalError != null) {
      return _OcrFatalErrorView(
        message: _fatalError!,
        onBackHome: () {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
        },
      );
    }

    if (!_isInitialized) {
      if (_isPreparingCamera || _isRequestingPermission) {
        return const _OcrLoadingView();
      }

      if (_permissionUiState == OcrPermissionUiState.preAsk) {
        return CameraPermissionPreAskView(
          onAllowCamera: _requestCameraPermission,
          onLater: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
          },
        );
      }

      return CameraPermissionDeniedView(
        onOpenSettings: () async {
          await openAppSettings();
        },
        onBack: () {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
        },
      );
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
                    Colors.black.withValues(alpha: 0.32),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.58),
                  ],
                  stops: const [0, 0.2, 0.62, 1],
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
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                compact ? 8 : 12,
                pagePadding,
                compact ? 14 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(compact ? 10 : 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Xác minh tài khoản',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Bước 1/4',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Chụp giấy tờ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Đưa mặt trước CCCD vào khung',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Hệ thống sẽ tự động chụp khi ảnh rõ và nằm đúng khung.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _toggleTorch,
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.42),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                        ),
                        icon: Icon(
                          _isTorchOn
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(compact ? 10 : 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mẹo chụp nhanh',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Đảm bảo giấy tờ nằm trọn trong khung và không bị lóa.',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: compact ? 9 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: AppMotion.fast,
                          child: Text(
                            _helperHints[_hintIndex],
                            key: ValueKey<int>(_hintIndex),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_isNavigating)
                              const Icon(
                                Icons.verified,
                                size: 16,
                                color: Colors.greenAccent,
                              )
                            else
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isNavigating
                                    ? 'Đã nhận diện rõ. Đang chuyển sang bước tiếp theo...'
                                    : 'Đang nhận diện...',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraPermissionPreAskView extends StatelessWidget {
  const CameraPermissionPreAskView({
    super.key,
    required this.onAllowCamera,
    required this.onLater,
  });

  final VoidCallback onAllowCamera;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cho phép dùng camera',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Camera được dùng để chụp giấy tờ và xác minh khuôn mặt của bạn.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bạn có thể cấp quyền ngay bây giờ để tiếp tục xác minh.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onAllowCamera,
                      child: const Text('Cho phép camera'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onLater,
                      child: const Text('Để sau'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CameraPermissionDeniedView extends StatelessWidget {
  const CameraPermissionDeniedView({
    super.key,
    required this.onOpenSettings,
    required this.onBack,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bật quyền camera để tiếp tục',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hãy mở cài đặt và cho phép ứng dụng sử dụng camera.',
                  ),
                  const SizedBox(height: 12),
                  const Text('1. Mở cài đặt'),
                  const SizedBox(height: 4),
                  const Text('2. Chọn Quyền truy cập'),
                  const SizedBox(height: 4),
                  const Text('3. Bật Camera'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onOpenSettings,
                      child: const Text('Mở cài đặt'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Quay lại'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OcrLoadingView extends StatelessWidget {
  const _OcrLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text('Đang chuẩn bị camera...'),
          ],
        ),
      ),
    );
  }
}

class _OcrFatalErrorView extends StatelessWidget {
  const _OcrFatalErrorView({required this.message, required this.onBackHome});

  final String message;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onBackHome,
                child: const Text('Quay lại'),
              ),
            ],
          ),
        ),
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
