import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/category.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/repository_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';

/// Manage categories.
///
/// Two tabs, because expense and income categories are never interchangeable —
/// a transaction's type determines which list it can choose from, and the
/// database enforces that.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  CategoryKind get _currentKind =>
      _tabController.index == 0 ? CategoryKind.expense : CategoryKind.income;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Income'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CategoryEditorSheet.show(context, kind: _currentKind),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(categoriesControllerProvider.notifier).refresh(),
        child: categories.view(
          (data) => TabBarView(
            controller: _tabController,
            children: [
              _CategoryList(
                categories:
                    data.where((c) => c.kind == CategoryKind.expense).toList(),
                kind: CategoryKind.expense,
              ),
              _CategoryList(
                categories:
                    data.where((c) => c.kind == CategoryKind.income).toList(),
                kind: CategoryKind.income,
              ),
            ],
          ),
          loading: const _CategoriesSkeleton(),
          onRetry: () =>
              ref.read(categoriesControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories, required this.kind});

  final List<Category> categories;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = categories.where((c) => !c.isArchived).toList();
    final archived = categories.where((c) => c.isArchived).toList();

    if (active.isEmpty && archived.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        title: 'No ${kind.label.toLowerCase()} categories',
        message: 'Create one to start organising your '
            '${kind.label.toLowerCase()}s.',
        actionLabel: 'New category',
        onAction: () => CategoryEditorSheet.show(context, kind: kind),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.giant,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
                _CategoryRow(category: active[i]),
              ],
            ],
          ),
        ),
        if (archived.isNotEmpty) ...[
          AppSpacing.gapXl,
          Text(
            'ARCHIVED',
            style: context.text.labelSmall
                ?.copyWith(color: context.palette.textSecondary),
          ),
          AppSpacing.gapXs,
          Text(
            'Archived categories stay on past transactions but are no longer '
            'offered when adding one.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < archived.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: AppSpacing.lg),
                  _CategoryRow(category: archived[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(categoryUsageProvider(category.id));

    return ListTile(
      onTap: () => CategoryEditorSheet.show(
        context,
        kind: category.kind,
        existing: category,
      ),
      leading: IconBadge(
        icon: category.icon,
        color: category.isArchived
            ? context.palette.textTertiary
            : category.color,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: context.text.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (category.isSystem)
            AppChipLabel(
              label: 'Default',
              color: context.palette.textTertiary,
              dense: true,
            ),
        ],
      ),
      subtitle: usage.maybeWhen(
        data: (count) => Text(
          count == 0
              ? 'Not used yet'
              : 'Used by $count transaction${count == 1 ? '' : 's'}',
          style: context.text.bodySmall,
        ),
        orElse: () => null,
      ),
      trailing: _CategoryMenu(category: category),
    );
  }
}

class _CategoryMenu extends ConsumerWidget {
  const _CategoryMenu({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await CategoryEditorSheet.show(
              context,
              kind: category.kind,
              existing: category,
            );
          case 'archive':
            await _toggleArchive(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            leading: Icon(
              category.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(category.isArchived ? 'Restore' : 'Archive'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        // Default categories are never deletable: they are part of every
        // account's starting set, and archiving achieves what a user wants.
        if (!category.isSystem)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: context.palette.danger,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: context.palette.danger),
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
      ],
    );
  }

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final archiving = !category.isArchived;
    await AppFeedback.runWithProgress(
      context,
      successMessage:
          archiving ? 'Category archived' : 'Category restored',
      action: () => ref
          .read(categoriesControllerProvider.notifier)
          .setArchived(category.id, archived: archiving),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final usage =
        await ref.read(categoryRepositoryProvider).usageCount(category.id);

    if (!context.mounted) return;

    if (usage > 0) {
      final archiveInstead = await AppFeedback.confirm(
        context,
        title: 'Cannot delete this category',
        message: 'It is used by $usage transaction${usage == 1 ? '' : 's'}. '
            'Deleting it would change your past reports.',
        confirmLabel: 'Archive instead',
      );
      if (archiveInstead && context.mounted) {
        await _toggleArchive(context, ref);
      }
      return;
    }

    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Delete category?',
      message: 'Nothing uses this category, so deleting it is safe.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await AppFeedback.runWithProgress(
      context,
      successMessage: 'Category deleted',
      action: () => ref
          .read(categoriesControllerProvider.notifier)
          .delete(category.id),
    );
  }
}

/// Create or edit a category in a sheet.
///
/// A sheet rather than a screen because the form is four fields and keeping the
/// list visible behind it makes the effect of a change obvious.
class CategoryEditorSheet extends ConsumerStatefulWidget {
  const CategoryEditorSheet({super.key, required this.kind, this.existing});

  final CategoryKind kind;
  final Category? existing;

  static Future<void> show(
    BuildContext context, {
    required CategoryKind kind,
    Category? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        // Lifts the sheet above the keyboard so the name field stays visible.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CategoryEditorSheet(kind: kind, existing: existing),
      ),
    );
  }

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _iconName;
  Color? _color;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _iconName = widget.existing?.iconName;
    _color = widget.existing == null
        ? null
        : AppColors.tryParseHex(widget.existing!.colorHex);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    final controller = ref.read(categoriesControllerProvider.notifier);

    try {
      if (widget.existing != null) {
        await controller.save(
          widget.existing!.copyWith(
            name: _nameController.text.trim(),
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
          ),
        );
      } else {
        await controller.create(
          Category(
            id: '',
            userId: '',
            name: _nameController.text.trim(),
            kind: widget.kind,
            iconName: _iconName,
            colorHex: _color == null ? null : AppColors.toHex(_color!),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      AppFeedback.showSuccess(
        context,
        widget.existing != null ? 'Category updated' : 'Category created',
      );
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = _color ?? context.colors.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing != null
                    ? 'Edit category'
                    : 'New ${widget.kind.label.toLowerCase()} category',
                style: context.text.titleLarge,
              ),
              AppSpacing.gapXl,

              Center(
                child: IconBadge(
                  icon: CategoryIcons.resolve(_iconName, widget.kind),
                  color: previewColor,
                  size: 56,
                ),
              ),
              AppSpacing.gapXl,

              TextFormField(
                controller: _nameController,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.words,
                validator: Validators.categoryName,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Name *'),
              ),
              AppSpacing.gapLg,

              Row(
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Icon',
                      value: _iconName ?? 'Default',
                      onTap: () async {
                        final picked = await IconPicker.show(
                          context,
                          selectedName: _iconName,
                        );
                        if (picked != null) {
                          setState(() => _iconName = picked);
                        }
                      },
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: PickerField(
                      label: 'Colour',
                      value: _color == null ? 'Default' : 'Custom',
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: previewColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () async {
                        final picked = await ColorPicker.show(
                          context,
                          selected: _color,
                        );
                        if (picked != null) setState(() => _color = picked);
                      },
                    ),
                  ),
                ],
              ),
              AppSpacing.gapXxl,

              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.existing != null
                            ? 'Save changes'
                            : 'Create category',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        CardSkeleton(height: 320),
      ],
    );
  }
}
