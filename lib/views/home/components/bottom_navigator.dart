// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:words625/views/theme.dart';

class BottomNavigator extends StatelessWidget {
  final Function(int) onPress;
  final int currentIndex;

  const BottomNavigator({
    required this.currentIndex,
    required this.onPress,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 64 + bottomPadding,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _NavItem(
              icon: Icons.school_rounded,
              label: 'Learn',
              isSelected: currentIndex == 0,
              onTap: () => onPress(0),
            ),
            _NavItem(
              icon: Icons.translate_rounded,
              label: 'Script',
              isSelected: currentIndex == 1,
              onTap: () => onPress(1),
            ),
            _NavItem(
              icon: Icons.person_rounded,
              label: 'Profile',
              isSelected: currentIndex == 2,
              onTap: () => onPress(2),
            ),
            _NavItem(
              icon: Icons.storefront_rounded,
              label: 'Shop',
              isSelected: currentIndex == 3,
              onTap: () => onPress(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? VarnamalaTheme.peacockTeal.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected
                  ? VarnamalaTheme.peacockTeal
                  : VarnamalaTheme.textHint,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}