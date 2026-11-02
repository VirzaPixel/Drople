import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/l10n.dart';
import '../screens/profile_screen.dart';
import '../theme/app_theme.dart';

const double kHeaderHeight = 64;
const double kNavHeight = 66;

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kHeaderHeight);

  void _openProfile(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  void _toggleLanguage() {
    final controller = AppLanguageController.instance;
    controller.setLanguage(
      controller.language == AppLanguage.indonesian
          ? AppLanguage.english
          : AppLanguage.indonesian,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppBar(
      toolbarHeight: kHeaderHeight,
      titleSpacing: 16,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.surface.withValues(alpha: 0.96),
      shape: const Border(
        bottom: BorderSide(color: AppColors.surfaceContainerHigh),
      ),
      title: Text(
        'Drople',
        style: inter(
          16,
          weight: FontWeight.w700,
          color: AppColors.onSurface,
          letterSpacing: 0.4,
        ),
      ),
      actions: [
        _HeaderButton(
          tooltip: l.t('app.language'),
          onTap: _toggleLanguage,
          size: 28,
          child: _LanguageFlag(
            english:
                AppLanguageController.instance.language == AppLanguage.english,
          ),
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          tooltip: l.t('app.profile'),
          icon: Icons.person_outline_rounded,
          onTap: () => _openProfile(context),
          highlighted: true,
        ),
        const SizedBox(width: 14),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.child,
    this.highlighted = false,
    this.size = 36,
  }) : assert(icon != null || child != null);

  final String tooltip;
  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final bool highlighted;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
          shape: highlighted
              ? CircleBorder(
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                )
              : const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child:
                child ??
                Icon(
                  icon,
                  size: 18,
                  color: highlighted
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class _LanguageFlag extends StatelessWidget {
  const _LanguageFlag({required this.english});

  final bool english;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: CustomPaint(
          painter: english ? _UkFlagPainter() : _IndonesiaFlagPainter(),
        ),
      ),
    );
  }
}

class _IndonesiaFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFCE1126),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UkFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF012169),
    );

    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = h * 0.22
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset.zero, Offset(w, h), white);
    canvas.drawLine(Offset(w, 0), Offset(0, h), white);

    final redDiagonal = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = h * 0.09
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset.zero, Offset(w, h), redDiagonal);
    canvas.drawLine(Offset(w, 0), Offset(0, h), redDiagonal);

    canvas.drawRect(
      Rect.fromLTWH(w * 0.39, 0, w * 0.22, h),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.36, w, h * 0.28),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.44, 0, w * 0.12, h),
      Paint()..color = const Color(0xFFC8102E),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.43, w, h * 0.14),
      Paint()..color = const Color(0xFFC8102E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NavItemData {
  const NavItemData(this.icon, this.label, {this.selectedIcon});

  final IconData icon;
  final String label;
  final IconData? selectedIcon;
}

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavItemData> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  Widget _item(BuildContext context, int i) {
    final item = items[i];
    final active = i == currentIndex;
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(i),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(item.icon, size: 20, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: inter(
                    10.5,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(bottom: bottom),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.surfaceContainerHigh),
            ),
          ),
          child: SizedBox(
            height: kNavHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < items.length; i++) _item(context, i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavItemData> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.surfaceContainerHigh),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
            child: Text(
              L10n.of(context).t('nav.menu'),
              style: inter(
                9,
                weight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1.5,
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++)
            _SideNavItem(
              item: items[i],
              active: i == currentIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NavItemData item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  active ? item.selectedIcon ?? item.icon : item.icon,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(
                      13,
                      weight: active ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (active)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double kContentTop = 16;
const double kContentBottom = 28;

class ScreenList extends StatelessWidget {
  const ScreenList({
    super.key,
    required this.children,
    this.gap = 14,
    this.maxWidth = 900,
  });

  final List<Widget> children;
  final double gap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            16,
            kContentTop,
            16,
            kContentBottom,
          ),
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
