import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/transaction_query.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/profile_providers.dart';
import '../../../shared/providers/transaction_providers.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pickers.dart';

/// The filter sheet.
///
/// Edits a local copy and applies it on "Show results", rather than refetching
/// on every tap. Combining several facets is the normal case here, and a query
/// per checkbox would make the sheet feel sluggish and waste requests the user
/// never wanted.
class TransactionFilterSheet extends ConsumerStatefulWidget {
  const TransactionFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (context) => const TransactionFilterSheet(),
    );
  }

  @override
  ConsumerState<TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState
    extends ConsumerState<TransactionFilterSheet> {
  late TransactionQuery _draft;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(transactionQueryProvider);
    _minController = TextEditingController(
      text: _draft.minAmount?.toEditableString() ?? '',
    );
    _maxController = TextEditingController(
      text: _draft.maxAmount?.toEditableString() ?? '',
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _apply() {
    final currency = ref.read(currencyProvider);
    final min = Money.tryParse(_minController.text, currency);
    final max = Money.tryParse(_maxController.text, currency);

    // A reversed range is almost certainly a slip; swap rather than returning
    // nothing and leaving the user to work out why.
    final ordered = (min != null && max != null && min > max)
        ? (min: max, max: min)
        : (min: min, max: max);

    ref.read(transactionQueryProvider.notifier).apply(
          _draft.copyWith(minAmount: ordered.min, maxAmount: ordered.max),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final accounts = ref.watch(activeAccountsProvider);
    final expenseCategories =
        ref.watch(categoriesByKindProvider(CategoryKind.expense));
    final incomeCategories =
        ref.watch(categoriesByKindProvider(CategoryKind.income));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding
          (
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: Text('Filters', style: context.text.titleLarge)),
              TextButton(
                onPressed: () {
                  setState(() {
                    _draft = _draft.clearFilters();
                    _minController.clear();
                    _maxController.clear();
                  });
                },
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            children: [
              _FilterSection(
                title: 'Type',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final type in TransactionType.values)
                      FilterChip(
                        label: Text(type.label),
                        selected: _draft.types.contains(type),
                        onSelected: (_) => setState(() {
                          final next = Set<TransactionType>.from(_draft.types);
                          next.contains(type)
                              ? next.remove(type)
                              : next.add(type);
                          _draft = _draft.copyWith(types: next);
                        }),
                      ),
                  ],
                ),
              ),

              _FilterSection(
                title: 'Period',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final preset in [
                          DateRangePreset.week,
                          DateRangePreset.month,
                          DateRangePreset.threeMonths,
                          DateRangePreset.year,
                        ])
                          FilterChip(
                            label: Text(preset.label),
                            selected: _draft.dateRange ==
                                AppDateUtils.rangeFor(preset),
                            onSelected: (selected) => setState(() {
                              _draft = _draft.copyWith(
                                dateRange: selected
                                    ? AppDateUtils.rangeFor(preset)
                                    : null,
                              );
                            }),
                          ),
                      ],
                    ),
                    AppSpacing.gapMd,
                    OutlinedButton.icon(
                      onPressed: () async {
                        final range = await DateTimePickers.pickRange(
                          context,
                          initial: _draft.dateRange,
                        );
                        if (range != null) {
                          setState(() => _draft = _draft.copyWith(
                                dateRange: range,
                              ));
                        }
                      },
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        _draft.dateRange?.label ?? 'Custom range',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ],
                ),
              ),

              _FilterSection(
                title: 'Amount',
                child: Row(
                  children: [
                    Expanded(
                      child: AmountField(
                        controller: _minController,
                        currency: currency,
                        label: 'From',
                        compact: true,
                      ),
                    ),
                    AppSpacing.hGapMd,
                    Expanded(
                      child: AmountField(
                        controller: _maxController,
                        currency: currency,
                        label: 'To',
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),

              if (accounts.isNotEmpty)
                _FilterSection(
                  title: 'Accounts',
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final account in accounts)
                        FilterChip(
                          avatar: IconBadge(
                            icon: account.icon,
                            color: account.color,
                            size: 20,
                            iconSize: 12,
                          ),
                          label: Text(account.name),
                          selected: _draft.accountIds.contains(account.id),
                          onSelected: (_) => setState(() {
                            final next = Set<String>.from(_draft.accountIds);
                            next.contains(account.id)
                                ? next.remove(account.id)
                                : next.add(account.id);
                            _draft = _draft.copyWith(accountIds: next);
                          }),
                        ),
                    ],
                  ),
                ),

              if (expenseCategories.isNotEmpty || incomeCategories.isNotEmpty)
                _FilterSection(
                  title: 'Categories',
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final category in [
                        ...expenseCategories,
                        ...incomeCategories,
                      ])
                        FilterChip(
                          avatar: Icon(
                            category.icon,
                            size: 14,
                            color: category.color,
                          ),
                          label: Text(category.name),
                          selected: _draft.categoryIds.contains(category.id),
                          onSelected: (_) => setState(() {
                            final next = Set<String>.from(_draft.categoryIds);
                            next.contains(category.id)
                                ? next.remove(category.id)
                                : next.add(category.id);
                            _draft = _draft.copyWith(categoryIds: next);
                          }),
                        ),
                    ],
                  ),
                ),

              _FilterSection(
                title: 'Payment method',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final method in PaymentMethod.values)
                      FilterChip(
                        label: Text(method.label),
                        selected: _draft.paymentMethods.contains(method),
                        onSelected: (_) => setState(() {
                          final next =
                              Set<PaymentMethod>.from(_draft.paymentMethods);
                          next.contains(method)
                              ? next.remove(method)
                              : next.add(method);
                          _draft = _draft.copyWith(paymentMethods: next);
                        }),
                      ),
                  ],
                ),
              ),

              _FilterSection(
                title: 'Source',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final source in TransactionSource.values)
                      FilterChip(
                        label: Text(source.label),
                        selected: _draft.sources.contains(source),
                        onSelected: (_) => setState(() {
                          final next =
                              Set<TransactionSource>.from(_draft.sources);
                          next.contains(source)
                              ? next.remove(source)
                              : next.add(source);
                          _draft = _draft.copyWith(sources: next);
                        }),
                      ),
                  ],
                ),
              ),

              _FilterSection(
                title: 'Other',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _draft.statuses.contains(TransactionStatus.pending),
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          statuses: value
                              ? {TransactionStatus.pending}
                              : const <TransactionStatus>{},
                        );
                      }),
                      title: Text(
                        'Only drafts',
                        style: context.text.titleSmall,
                      ),
                      subtitle: Text(
                        'Transactions saved but not yet confirmed',
                        style: context.text.bodySmall,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _draft.onlyWithAttachments,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(onlyWithAttachments: value);
                      }),
                      title: Text(
                        'Only with receipts',
                        style: context.text.titleSmall,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: !_draft.includeTransfers,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(includeTransfers: !value);
                      }),
                      title: Text(
                        'Hide transfers',
                        style: context.text.titleSmall,
                      ),
                      subtitle: Text(
                        'Transfers move money between your own accounts',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: FilledButton(
              onPressed: _apply,
              child: const Text('Show results'),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          AppSpacing.gapMd,
          child,
        ],
      ),
    );
  }
}
