import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4FAFB), Color(0xFFF8FAFE)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(pagePadding),
            children: [
              Text(
                'Xác minh danh tính',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: compact ? 28 : 32,
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Text(
                'Chỉ mất khoảng 2 phút để xác minh và bảo vệ tài khoản của bạn.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              SizedBox(height: compact ? 18 : 22),
              const _PrepItem(
                icon: Icons.badge_outlined,
                title: 'Chuẩn bị CCCD',
                subtitle: 'Dùng CCCD bản gốc, còn hạn',
              ),
              SizedBox(height: compact ? 8 : 10),
              const _PrepItem(
                icon: Icons.wb_sunny_outlined,
                title: 'Đứng ở nơi đủ sáng',
                subtitle: 'Tránh lóa hoặc quá tối khi quét',
              ),
              SizedBox(height: compact ? 8 : 10),
              const _PrepItem(
                icon: Icons.face_retouching_natural,
                title: 'Quét khuôn mặt trong vài giây',
                subtitle: 'Giữ khuôn mặt rõ và nhìn thẳng vào màn hình',
              ),
              SizedBox(height: compact ? 16 : 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Gồm 4 bước ngắn: giấy tờ · thông tin · khuôn mặt · kết quả',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizedBox(height: compact ? 18 : 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.ocr);
                  },
                  child: const Text('Bắt đầu xác minh'),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              Text(
                'Thông tin chỉ được dùng để xác minh tài khoản',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrepItem extends StatelessWidget {
  const _PrepItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
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
                  title,
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
