import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_theme.dart';
import 'screens/face_scan_screen.dart';
import 'screens/ocr_camera_screen.dart';
import 'screens/platform_fallback_screens.dart';
import 'screens/result_screen.dart';
import 'screens/review_screen.dart';
import 'screens/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = <CameraDescription>[];
  final isOcrSupportedPlatform = _isMobileOcrPlatform;

  if (isOcrSupportedPlatform) {
    try {
      cameras = await availableCameras();
    } catch (error) {
      debugPrint('Không thể lấy danh sách camera: $error');
    }
  }

  runApp(
    EkycApp(cameras: cameras, isOcrSupportedPlatform: isOcrSupportedPlatform),
  );
}

bool get _isMobileOcrPlatform {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

class EkycApp extends StatelessWidget {
  const EkycApp({
    super.key,
    required this.cameras,
    this.isOcrSupportedPlatform = true,
  });

  final List<CameraDescription> cameras;
  final bool isOcrSupportedPlatform;

  String get _initialRoute {
    if (!isOcrSupportedPlatform) {
      return AppRoutes.unsupported;
    }
    if (cameras.isEmpty) {
      return AppRoutes.noCamera;
    }
    return AppRoutes.welcome;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eKYC Simulator (Privacy-First)',
      theme: AppTheme.light(),
      initialRoute: _initialRoute,
      routes: {
        AppRoutes.welcome: (_) => const WelcomeScreen(),
        AppRoutes.review: (_) => const ReviewScreen(),
        AppRoutes.face: (_) => const FaceScanScreen(),
        AppRoutes.result: (_) => const ResultScreen(),
        AppRoutes.unsupported: (_) => const UnsupportedPlatformScreen(),
        AppRoutes.noCamera: (_) => const NoCameraScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.ocr) {
          if (!isOcrSupportedPlatform) {
            return MaterialPageRoute<void>(
              builder: (_) => const UnsupportedPlatformScreen(),
              settings: settings,
            );
          }

          if (cameras.isEmpty) {
            return MaterialPageRoute<void>(
              builder: (_) => const NoCameraScreen(),
              settings: settings,
            );
          }

          return MaterialPageRoute<void>(
            builder: (_) => OcrCameraScreen(cameras: cameras),
            settings: settings,
          );
        }

        return MaterialPageRoute<void>(
          builder: (_) => const WelcomeScreen(),
          settings: settings,
        );
      },
    );
  }
}
