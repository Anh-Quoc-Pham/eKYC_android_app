import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../app_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introController;
  late final Animation<double> _headerReveal;
  late final Animation<double> _cardsReveal;
  late final Animation<double> _ctaReveal;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _headerReveal = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, 0.45, curve: AppMotion.emphasized),
    );
    _cardsReveal = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.25, 0.75, curve: AppMotion.standard),
    );
    _ctaReveal = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.6, 1, curve: AppMotion.gentle),
    );

    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    return Scaffold(
      body: AnimatedBuilder(
        animation: _introController,
        builder: (context, _) {
          final drift = math.sin(_introController.value * math.pi * 2) * 8;

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFDFF3F2),
                      const Color(0xFFF7FBFF),
                      AppColors.accent.withValues(alpha: 0.16),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -80 + drift,
                right: -60,
                child: _BlurBubble(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  size: compact ? 180 : 220,
                ),
              ),
              Positioned(
                bottom: -70 - drift,
                left: -40,
                child: _BlurBubble(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  size: compact ? 170 : 200,
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.all(pagePadding),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - (pagePadding * 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: compact ? 8 : 18),
                            _Reveal(
                              animation: _headerReveal,
                              offsetY: compact ? 12 : 18,
                              child: Text(
                                'eKYC Privacy-First',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontSize: compact ? 26 : 30),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 10),
                            _Reveal(
                              animation: _headerReveal,
                              offsetY: compact ? 10 : 14,
                              child: Text(
                                'Xác thực danh tính theo luồng OCR -> Face -> ZKP, giữ dữ liệu nhạy cảm trên thiết bị.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            SizedBox(height: compact ? 16 : 24),
                            _Reveal(
                              animation: _cardsReveal,
                              offsetY: compact ? 12 : 16,
                              child: _StepCard(
                                index: '01',
                                title: 'Quét CCCD',
                                subtitle:
                                    'OCR realtime nhận diện số CCCD, họ tên, ngày sinh.',
                                icon: Icons.badge_outlined,
                                compact: compact,
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 10),
                            _Reveal(
                              animation: _cardsReveal,
                              offsetY: compact ? 12 : 16,
                              child: _StepCard(
                                index: '02',
                                title: 'Face & Liveness',
                                subtitle:
                                    'Yêu cầu ngẫu nhiên blink/smile để chống spoofing.',
                                icon: Icons.face_retouching_natural,
                                compact: compact,
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 10),
                            _Reveal(
                              animation: _cardsReveal,
                              offsetY: compact ? 12 : 16,
                              child: _StepCard(
                                index: '03',
                                title: 'ZKP Verify',
                                subtitle:
                                    'Gửi proof xác minh lên backend, không lộ PII thô.',
                                icon: Icons.verified_user_outlined,
                                compact: compact,
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 36),
                            _Reveal(
                              animation: _ctaReveal,
                              offsetY: 12,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed(AppRoutes.ocr);
                                  },
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Bắt đầu eKYC'),
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 10),
                            _Reveal(
                              animation: _ctaReveal,
                              offsetY: 8,
                              child: Text(
                                'Demo tốt nhất trên Android/iOS có camera trước và sau.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.compact,
  });

  final String index;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 44,
            height: compact ? 40 : 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$index  $title',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurBubble extends StatelessWidget {
  const _BlurBubble({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.25, 1],
          ),
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.offsetY,
    required this.child,
  });

  final Animation<double> animation;
  final double offsetY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final dy = (1 - animation.value) * offsetY;
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
      ),
    );
  }
}
