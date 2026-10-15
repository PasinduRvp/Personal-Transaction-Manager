import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ocr/presentation/import_source_sheet.dart';
import '../../shared/providers/core_providers.dart';
import '../constants/enums.dart';
import '../extensions/context_extensions.dart';
import '../theme/app_spacing.dart';
import 'app_routes.dart';

/// The five-tab shell.
///
/// Uses a StatefulNavigationShell so each tab keeps its own navigation stack and
/// scroll position — switching away from a half-scrolled transaction list and
/// back should not reset it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      body: Column(
        children: [
          // Above the tab content rather than inside it, so it is visible on
          // every tab without each screen having to render it.
          if (isOffline) SafeArea(bottom: false, child: const OfflineStrip()),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: _BottomNav(navigationShell: navigationShell),
      floatingActionButton: const _AddFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class OfflineStrip extends StatelessWidget {
  const OfflineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.palette.warning
          .withValues(alpha: context.isDark ? 0.2 : 0.14),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 15,
            color: context.palette.warning,
          ),
          AppSpacing.hGapSm,
          Text(
            'Offline — showing saved data',
            style: context.text.labelMedium
                ?.copyWith(color: context.palette.warning),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xD811181F)
                : const Color(0xD8FFFFFF),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Transactions',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline_rounded),
                selectedIcon: Icon(Icons.pie_chart_rounded),
                label: 'Budgets',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Analytics',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The central add button.
///
/// Opens a menu rather than one fixed action, because there are four things a
/// user might be here to do and guessing wrong costs them a tap either way.
class _AddFab extends StatelessWidget {
  const _AddFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => AddMenuSheet.show(context),
      tooltip: 'Add',
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}

/// The add menu.
class AddMenuSheet extends StatelessWidget {
  const AddMenuSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const AddMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add', style: context.text.titleLarge),
              AppSpacing.gapXl,
  
              _AddOption(
                icon: Icons.arrow_upward_rounded,
                color: context.palette.expense,
                title: 'Expense',
                subtitle: 'Money you spent',
                onTap: () => _go(
                  context,
                  '${AppRoutes.transactionAdd}?type=${TransactionType.expense.wire}',
                ),
              ),
              _AddOption(
                icon: Icons.arrow_downward_rounded,
                color: context.palette.income,
                title: 'Income',
                subtitle: 'Money you received',
                onTap: () => _go(
                  context,
                  '${AppRoutes.transactionAdd}?type=${TransactionType.income.wire}',
                ),
              ),
              _AddOption(
                icon: Icons.swap_horiz_rounded,
                color: context.palette.transfer,
                title: 'Transfer',
                subtitle: 'Between your own accounts',
                onTap: () => _go(
                  context,
                  '${AppRoutes.transactionAdd}?type=${TransactionType.transfer.wire}',
                ),
              ),
  
              AppSpacing.gapSm,
              const Divider(),
              AppSpacing.gapSm,
  
              _AddOption(
                icon: Icons.document_scanner_outlined,
                color: context.colors.primary,
                title: 'Import document',
                subtitle: 'Photograph a receipt or upload a statement',
                onTap: () {
                  Navigator.of(context).pop();
                  ImportSourceSheet.show(context);
                },
                isHighlighted: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _go(BuildContext context, String location) {
    Navigator.of(context).pop();
    context.push(location);
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isHighlighted = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material
        (
        color: isHighlighted
            ? color.withValues(alpha: context.isDark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDark ? 0.22 : 0.12),
                    borderRadius: AppRadius.mdAll,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: color),
                ),
                AppSpacing.hGapLg,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(subtitle, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
