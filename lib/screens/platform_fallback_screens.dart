import 'package:flutter/material.dart';

class UnsupportedPlatformScreen extends StatelessWidget {
  const UnsupportedPlatformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _FallbackScaffold(
      icon: Icons.desktop_windows_outlined,
      title: 'Nền tảng chưa hỗ trợ',
      message: 'OCR realtime hiện chỉ hỗ trợ Android và iOS.',
    );
  }
}

class NoCameraScreen extends StatelessWidget {
  const NoCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _FallbackScaffold(
      icon: Icons.camera_alt_outlined,
      title: 'Không có camera',
      message: 'Không tìm thấy camera khả dụng trên thiết bị này.',
    );
  }
}

class _FallbackScaffold extends StatelessWidget {
  const _FallbackScaffold({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
