import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../config/app_config.dart';
import '../models/decision_models.dart';
import '../services/device_trust_service.dart';
import '../services/ekyc_session.dart';
import '../services/zkp_service.dart';

enum LivenessAction { blink, smile }

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key, this.backendBaseUrl});

  final String? backendBaseUrl;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  _FaceScanScreenState()
    : _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: true,
          enableClassification: true,
          enableContours: false,
        ),
      );

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  final FaceDetector _faceDetector;
  final EkycSession _session = EkycSession.instance;
  final DeviceTrustService _deviceTrustService = DeviceTrustService();
  late final ZkpService _zkpService;

  CameraController? _cameraController;
  String? _errorMessage;
  bool _isInitialized = false;
  bool _isProcessingFrame = false;
  bool _isSubmittingToServer = false;

  bool _faceDetected = false;
  bool _livenessPassed = false;
  bool _faceMatchPassed = false;

  bool _eyesWereOpen = false;
  int _smileFrameStreak = 0;

  double _matchScore = 0;
  Map<String, double>? _referenceSignature;

  late final LivenessAction _requiredAction;
  String _statusText = 'Đang nhận diện khuôn mặt...';

  DateTime _lastScanTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scanDebounce = Duration(milliseconds: 280);

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isMobileVisionPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _canProceed => _livenessPassed && _faceMatchPassed;

  String get _activeFullName {
    if (_session.fullName.isEmpty) {
      return 'Chưa có dữ liệu OCR';
    }
    return _session.fullName;
  }

  String get _activeIdHash => _session.cccdHash;

  String get _challengeLabel {
    switch (_requiredAction) {
      case LivenessAction.blink:
        return 'Hành động ngẫu nhiên: Nháy mắt 1 lần';
      case LivenessAction.smile:
        return 'Hành động ngẫu nhiên: Mỉm cười nhẹ';
    }
  }

  double get _progress {
    if (_canProceed) {
      return 1;
    }

    var value = 0.1;
    if (_faceDetected) {
      value += 0.35;
    }
    if (_livenessPassed) {
      value += 0.35;
      value += _matchScore * 0.2;
    }

    return value.clamp(0, 0.99);
  }

  @override
  void initState() {
    super.initState();
    _zkpService = ZkpService(
      baseUrl: widget.backendBaseUrl ?? AppConfig.apiBaseUrl,
    );
    _requiredAction = Random().nextBool()
        ? LivenessAction.blink
        : LivenessAction.smile;

    if (!_session.hasOcrData) {
      _errorMessage =
          'Thiếu dữ liệu OCR trong phiên làm việc. Hãy quay lại bước quét CCCD.';
      return;
    }

    _initializeCamera();
  }

  Future<void> _submitPhase3Verification() async {
    if (_isSubmittingToServer || !_canProceed || _activeIdHash.isEmpty) {
      return;
    }

    setState(() {
      _isSubmittingToServer = true;
      _statusText = 'Đang đóng gói ZKP Proof và gửi lên server...';
    });

    try {
      _session.registerVerificationAttempt();

      final cccd = await _secureStorage.read(key: 'ekyc.cccd') ?? '';
      final dateOfBirth =
          await _secureStorage.read(key: 'ekyc.date_of_birth') ?? '';
      final trustSignal = await _deviceTrustService.evaluate();

      final riskContext = VerificationRiskContext(
        ocr: _session.ocrRiskSignals,
        face: FaceRiskSignals(
          matchScore: _matchScore,
          livenessConfidence: _livenessPassed ? 0.9 : 0.45,
        ),
        deviceTrust: trustSignal,
        retry: RetrySignals(
          attemptCount: _session.verificationAttemptCount,
          maxAttempts: 3,
        ),
      );

      final piiPayload = <String, dynamic>{
        'full_name': _activeFullName,
        'date_of_birth': dateOfBirth,
        'cccd_last4': cccd.length >= 4 ? cccd.substring(cccd.length - 4) : cccd,
        'liveness_action': _requiredAction.name,
        'face_match_score': _matchScore,
        'verified_at': DateTime.now().toIso8601String(),
      };

      final result = await _zkpService.submitPhase3(
        idHash: _activeIdHash,
        pii: piiPayload,
        riskContext: riskContext,
        enrollIfNeeded: true,
      );

      _session.setFaceState(
        livenessPassed: _livenessPassed,
        faceMatchPassed: _faceMatchPassed,
        faceMatchScore: _matchScore,
      );
      _session.setVerificationResult(
        succeeded: result.decision.isPass,
        statusCode: result.statusCode,
        message: result.message,
        payload: result.payload,
        decision: result.decision,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacementNamed(AppRoutes.result);
    } catch (error) {
      final fallbackDecision = DecisionOutcome.networkInterrupted();
      _session.setFaceState(
        livenessPassed: _livenessPassed,
        faceMatchPassed: _faceMatchPassed,
        faceMatchScore: _matchScore,
      );
      _session.setVerificationResult(
        succeeded: false,
        statusCode: 0,
        message: 'network_error: $error',
        payload: const <String, dynamic>{},
        decision: fallbackDecision,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacementNamed(AppRoutes.result);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingToServer = false;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (!_isMobileVisionPlatform) {
      setState(() {
        _errorMessage = 'Face Scan chỉ hỗ trợ Android và iOS.';
      });
      return;
    }

    final permissionStatus = await Permission.camera.request();
    if (!permissionStatus.isGranted) {
      setState(() {
        _errorMessage =
            'Camera permission bị từ chối. Vui lòng cấp quyền để quét khuôn mặt.';
      });
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() {
        _errorMessage = 'Không tìm thấy camera trên thiết bị.';
      });
      return;
    }

    final selectedCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
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
        _errorMessage = 'Không thể khởi tạo camera trước: $error';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessingFrame || !mounted || _canProceed) {
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

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _faceDetected = false;
            _statusText = 'Không thấy khuôn mặt. Hãy đưa mặt vào khung tròn.';
          });
        }
        return;
      }

      final face = _pickLargestFace(faces);
      _updateLivenessAndMatch(face);
    } catch (error) {
      debugPrint('Face detection error: $error');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Face _pickLargestFace(List<Face> faces) {
    return faces.reduce((current, next) {
      final currentArea =
          current.boundingBox.width * current.boundingBox.height;
      final nextArea = next.boundingBox.width * next.boundingBox.height;
      return nextArea > currentArea ? next : current;
    });
  }

  void _updateLivenessAndMatch(Face face) {
    final livenessResult = _evaluateLiveness(face);
    final signature = _buildFaceSignature(face);

    var matchScore = _matchScore;
    var faceMatchPassed = _faceMatchPassed;
    var status = _statusText;

    if (signature != null) {
      _referenceSignature ??= signature;

      if (_referenceSignature != null) {
        matchScore = _computeMatchScore(_referenceSignature!, signature);
        faceMatchPassed = matchScore >= 0.65;
      }
    } else {
      status = 'Đang lấy điểm mốc khuôn mặt... giữ đầu ổn định.';
      faceMatchPassed = false;
      matchScore = 0;
    }

    if (_livenessPassed || livenessResult.passed) {
      if (faceMatchPassed) {
        status = 'Đã xác thực liveness và face matching. Bạn có thể tiếp tục.';
      } else {
        status = 'Liveness đạt. Đang đối chiếu đặc trưng khuôn mặt...';
      }
    } else {
      status = livenessResult.message;
    }

    if (mounted) {
      setState(() {
        _faceDetected = true;
        _livenessPassed = _livenessPassed || livenessResult.passed;
        _faceMatchPassed = faceMatchPassed;
        _matchScore = matchScore;
        _statusText = status;
      });

      _session.setFaceState(
        livenessPassed: _livenessPassed,
        faceMatchPassed: _faceMatchPassed,
        faceMatchScore: _matchScore,
      );
    }
  }

  ({bool passed, String message}) _evaluateLiveness(Face face) {
    switch (_requiredAction) {
      case LivenessAction.blink:
        final left = face.leftEyeOpenProbability;
        final right = face.rightEyeOpenProbability;

        if (left == null || right == null) {
          return (
            passed: false,
            message: 'Giữ mặt thẳng camera để đọc trạng thái mắt (blink).',
          );
        }

        final avgEyeOpen = (left + right) / 2;
        if (avgEyeOpen > 0.72) {
          _eyesWereOpen = true;
        }

        if (_eyesWereOpen && avgEyeOpen < 0.35) {
          return (passed: true, message: 'Blink đã được ghi nhận.');
        }

        return (
          passed: false,
          message: 'Vui lòng nháy mắt 1 lần để hoàn tất liveness.',
        );

      case LivenessAction.smile:
        final smile = face.smilingProbability;
        if (smile == null) {
          return (
            passed: false,
            message: 'Giữ mặt rõ hơn để hệ thống nhận diện nụ cười.',
          );
        }

        if (smile > 0.75) {
          _smileFrameStreak++;
        } else {
          _smileFrameStreak = 0;
        }

        if (_smileFrameStreak >= 2) {
          return (passed: true, message: 'Nụ cười đã được ghi nhận.');
        }

        return (
          passed: false,
          message: 'Vui lòng mỉm cười nhẹ để hoàn tất liveness.',
        );
    }
  }

  Map<String, double>? _buildFaceSignature(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final mouthLeft = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final mouthRight = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (leftEye == null ||
        rightEye == null ||
        nose == null ||
        mouthLeft == null ||
        mouthRight == null) {
      return null;
    }

    final mouthCenter = Point<double>(
      (mouthLeft.x + mouthRight.x) / 2,
      (mouthLeft.y + mouthRight.y) / 2,
    );

    final eyeDistance = _distance(leftEye, rightEye);
    if (eyeDistance <= 0) {
      return null;
    }

    final noseToMouth = _distance(nose, mouthCenter);
    final leftEyeToNose = _distance(leftEye, nose);
    final rightEyeToNose = _distance(rightEye, nose);

    // Dùng tỉ lệ hình học để mô phỏng face matching, không lưu ảnh thô.
    return {
      'nose_to_mouth_ratio': noseToMouth / eyeDistance,
      'left_eye_to_nose_ratio': leftEyeToNose / eyeDistance,
      'right_eye_to_nose_ratio': rightEyeToNose / eyeDistance,
    };
  }

  double _computeMatchScore(
    Map<String, double> reference,
    Map<String, double> current,
  ) {
    final keys = reference.keys.where(current.containsKey).toList();
    if (keys.isEmpty) {
      return 0;
    }

    var diffSum = 0.0;
    for (final key in keys) {
      diffSum += (reference[key]! - current[key]!).abs();
    }

    final meanDiff = diffSum / keys.length;
    final rawScore = 1 - (meanDiff / 0.6);
    return rawScore.clamp(0, 1);
  }

  double _distance(Point<num> p1, Point<num> p2) {
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy).toDouble();
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

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream();
      }
      controller.dispose();
    }
    _zkpService.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Scan')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.review,
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.arrow_back_outlined),
                  label: const Text('Quay lại Review'),
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
      appBar: AppBar(title: const Text('Face Matching & Liveness')),
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
                    Colors.black.withValues(alpha: 0.34),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.56),
                  ],
                  stops: const [0, 0.22, 0.66, 1],
                ),
              ),
            ),
          ),
          const _FaceCircleOverlay(),
          Positioned(
            top: compact ? 10 : 16,
            left: pagePadding,
            right: pagePadding,
            child: _TopInstructionCard(
              fullName: _activeFullName,
              challenge: _challengeLabel,
              compact: compact,
            ),
          ),
          Positioned(
            left: pagePadding,
            right: pagePadding,
            bottom: compact ? 16 : 24,
            child: _StatusCard(
              statusText: _statusText,
              progress: _progress,
              livenessPassed: _livenessPassed,
              faceMatchPassed: _faceMatchPassed,
              matchScore: _matchScore,
              canProceed: _canProceed,
              isSubmittingToServer: _isSubmittingToServer,
              onContinue: _canProceed ? _submitPhase3Verification : null,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopInstructionCard extends StatelessWidget {
  const _TopInstructionCard({
    required this.fullName,
    required this.challenge,
    required this.compact,
  });

  final String fullName;
  final String challenge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 11 : 14),
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
              const Icon(Icons.face_retouching_natural, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Người dùng: $fullName',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            challenge,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.statusText,
    required this.progress,
    required this.livenessPassed,
    required this.faceMatchPassed,
    required this.matchScore,
    required this.canProceed,
    required this.isSubmittingToServer,
    required this.onContinue,
    required this.compact,
  });

  final String statusText;
  final double progress;
  final bool livenessPassed;
  final bool faceMatchPassed;
  final double matchScore;
  final bool canProceed;
  final bool isSubmittingToServer;
  final VoidCallback? onContinue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cardColor = canProceed
        ? const Color(0xFF0E6B6B).withValues(alpha: 0.86)
        : Colors.black.withValues(alpha: 0.7);

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canProceed)
                const Icon(Icons.verified, color: Colors.greenAccent)
              else
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  switchInCurve: AppMotion.standard,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    statusText,
                    key: ValueKey<String>(statusText),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: livenessPassed ? 'Liveness: Đạt' : 'Liveness: Chưa đạt',
                positive: livenessPassed,
              ),
              _StatusPill(
                label: 'Match ${(matchScore * 100).toStringAsFixed(0)}%',
                positive: faceMatchPassed,
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSubmittingToServer ? null : onContinue,
              icon: isSubmittingToServer
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(
                isSubmittingToServer ? 'Đang gửi ZKP...' : 'Sang bước kết quả',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: positive
            ? Colors.greenAccent.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FaceCircleOverlay extends StatefulWidget {
  const _FaceCircleOverlay();

  @override
  State<_FaceCircleOverlay> createState() => _FaceCircleOverlayState();
}

class _FaceCircleOverlayState extends State<_FaceCircleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, _) {
          return CustomPaint(
            painter: _FaceCircleOverlayPainter(
              pulse: AppMotion.gentle.transform(_pulseController.value),
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _FaceCircleOverlayPainter extends CustomPainter {
  _FaceCircleOverlayPainter({required this.pulse});

  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.width, size.height) * 0.32;
    final center = Offset(size.width / 2, size.height * 0.45);

    final dimmedPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      dimmedPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final pulseRadius = radius + 10 + (pulse * 12);
    canvas.drawCircle(
      center,
      pulseRadius,
      Paint()
        ..color = const Color(0xFF5FD9D3).withValues(alpha: 0.22 * (1 - pulse))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            const Color(0xFF5FD9D3).withValues(alpha: 0.8),
            const Color(0xFFFF8A3D).withValues(alpha: 0.75),
            const Color(0xFF5FD9D3).withValues(alpha: 0.8),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (pulse * 1.4),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _FaceCircleOverlayPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}
