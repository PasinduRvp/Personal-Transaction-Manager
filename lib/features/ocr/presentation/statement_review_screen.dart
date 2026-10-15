import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/transaction_candidate.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/repositories/ocr_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/money_text.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';
import 'ocr_review_screen.dart';
import 'widgets/confidence_field.dart';
import 'widgets/document_preview.dart';

/// Reviewing a bank statement's rows.
///
/// A statement produces many candidates, so this is a selectable list rather
/// than a form: the user picks an account once, unticks anything they do not
/// want, opens individual rows that need fixing, and confirms the rest in one
/// go. Confirming each row through a separate modal would be unusable at twelve
/// transactions.
class StatementReviewScreen extends ConsumerStatefulWidget {
  const StatementReviewScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<StatementReviewScreen> createState() =>
      _StatementReviewScreenState();
}

class _StatementReviewScreenState
    extends ConsumerState<StatementReviewScreen> {
  final Set<String> _selected = {};
  Account? _account;
  bool _initialised = false;
  bool _isSubmitting = false;

  void _initialise(List<TransactionCandidate> candidates) {
    if (_initialised) return;
    _initialised = true;

    // Everything is selected by default *except* likely duplicates: the user
    // should have to opt in to creating one, not remember to opt out.
    _selected.addAll(
      candidates
          .where((c) =>
              c.status == OcrCandidateStatus.pending && !c.isPossibleDuplicate)
          .map((c) => c.id),
    );
    _account = ref.read(defaultAccountProvider);
  }

  Future<void> _confirmSelected(List<TransactionCandidate> candidates) async {
    final account = _account;
    if (account == null) {
      AppFeedback.showValidation(
        context,
        'Choose which account these transactions belong to.',
      );
      return;
    }

    final chosen = candidates
        .where((c) =>
            _selected.contains(c.id) &&
            c.status == OcrCandidateStatus.pending)
        .toList();

    if (chosen.isEmpty) {
      AppFeedback.showValidation(context, 'Select at least one transaction.');
      return;
    }

    // Rows the parser could not complete cannot be batch-confirmed — the user
    // has to open them. Saying which ones is more useful than a generic refusal.
    final incomplete = chosen
        .where((c) => c.amount == null || c.transactionDate == null)
        .toList();
    if (incomplete.isNotEmpty) {
      AppFeedback.showValidation(
        context,
        '${incomplete.length} selected '
        'transaction${incomplete.length == 1 ? '' : 's'} '
        '${incomplete.length == 1 ? 'is' : 'are'} missing an amount or date. '
        'Open and complete them first.',
      );
      return;
    }

    final duplicates = chosen.where((c) => c.isPossibleDuplicate).length;
    if (duplicates > 0) {
      final proceed = await AppFeedback.confirm(
        context,
        title: 'Include possible duplicates?',
        message: '$duplicates of the selected transactions look like ones you '
            'already have.',
        confirmLabel: 'Import anyway',
        cancelLabel: 'Go back',
      );
      if (!proceed || !mounted) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result =
          await ref.read(importControllerProvider.notifier).confirmMany([
        for (final candidate in chosen)
          CandidateConfirmation(
            candidate: candidate,
            accountId: account.id,
            amount: candidate.amount!,
            date: candidate.transactionDate!,
            type: candidate.type,
            categoryId: candidate.suggestedCategoryId,
            merchant: candidate.merchant,
            description: candidate.description,
            paymentMethod: candidate.paymentMethod,
            referenceNumber: candidate.referenceNumber,
          ),
      ]);

      if (!mounted) return;

      if (result.isCompleteSuccess) {
        AppFeedback.showSuccess(context, result.summary);
        context.go(AppRoutes.transactions);
        return;
      }

      // A partial failure is reported honestly rather than shown as success.
      await AppFeedback.confirm(
        context,
        title: result.isCompleteFailure
            ? 'Nothing could be saved'
            : 'Some transactions were not saved',
        message: result.summary,
        confirmLabel: 'OK',
        cancelLabel: 'Close',
        consequences: [
          for (final entry in result.failures.entries.take(4))
            entry.value.message,
        ],
      );

      if (mounted) setState(() => _selected.clear());
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final candidates = state.candidates;

    if (candidates.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review import')),
        body: const LoadingView(),
      );
    }

    _initialise(candidates);

    final pending = candidates
        .where((c) => c.status == OcrCandidateStatus.pending)
        .toList();
    final resolved = candidates
        .where((c) => c.status != OcrCandidateStatus.pending)
        .toList();

    final selectedCandidates =
        pending.where((c) => _selected.contains(c.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${candidates.length} transactions detected'),
        actions: [
          TextButton(
            onPressed: pending.isEmpty
                ? null
                : () => setState(() {
                      if (_selected.length == pending.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(pending.map((c) => c.id));
                      }
                    }),
            child: Text(
              _selected.length == pending.length ? 'Select none' : 'Select all',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.page),
                children: [
                  if (state.document != null) ...[
                    DocumentPreview(
                      document: state.document!,
                      height: 150,
                      onTap: () => DocumentViewerScreen.open(
                        context,
                        document: state.document!,
                      ),
                    ),
                    AppSpacing.gapLg,
                  ],

                  _AccountSelector(
                    account: _account,
                    onChanged: (account) =>
                        setState(() => _account = account),
                  ),
                  AppSpacing.gapLg,

                  if (pending.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'TO IMPORT',
                            style: context.text.labelSmall?.copyWith(
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${_selected.length} of ${pending.length} selected',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                    AppSpacing.gapMd,
                    for (final candidate in pending)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CandidateRow(
                          candidate: candidate,
                          isSelected: _selected.contains(candidate.id),
                          onToggle: () => setState(() {
                            _selected.contains(candidate.id)
                                ? _selected.remove(candidate.id)
                                : _selected.add(candidate.id);
                          }),
                          onOpen: () => _openCandidate(candidate, state),
                        ),
                      ),
                  ],

                  if (resolved.isNotEmpty) ...[
                    AppSpacing.gapLg,
                    Text(
                      'ALREADY HANDLED',
                      style: context.text.labelSmall
                          ?.copyWith(color: context.palette.textSecondary),
                    ),
                    AppSpacing.gapMd,
                    for (final candidate in resolved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _ResolvedRow(candidate: candidate),
                      ),
                  ],

                  AppSpacing.gapXl,
                  if (state.document != null)
                    RawTextPanel(documentId: state.document!.id),
                  AppSpacing.gapXxl,
                ],
              ),
            ),

            _StatementFooter(
              selected: selectedCandidates,
              isSubmitting: _isSubmitting,
              onConfirm: () => _confirmSelected(candidates),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCandidate(
    TransactionCandidate candidate,
    ImportState state,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OcrReviewScreen(
          candidate: candidate,
          document: state.document,
          position: state.candidates.indexOf(candidate) + 1,
          total: state.candidates.length,
          // Returns here rather than jumping to the transaction list, so the
          // user keeps working through the statement.
          onConfirmed: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) setState(() => _selected.remove(candidate.id));
  }
}

class _AccountSelector extends ConsumerWidget {
  const _AccountSelector({required this.account, required this.onChanged});

  final Account? account;
  final ValueChanged<Account> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);

    return AppCard(
      borderColor: account == null
          ? context.palette.danger.withValues(alpha: 0.45)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Which account is this statement for?',
                  style: context.text.titleSmall,
                ),
              ),
              if (account == null)
                ConfidenceBadge(level: ConfidenceLevel.missing),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            // Explaining why, because a user may reasonably expect the app to
            // know: the document does not say.
            'A statement does not identify which of your accounts it belongs '
            'to, so this one is up to you.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          PickerField(
            label: 'Account',
            isRequired: true,
            value: account?.name,
            leading: account == null
                ? null
                : IconBadge(
                    icon: account!.icon,
                    color: account!.color,
                    size: 24,
                    iconSize: 14,
                  ),
            onTap: () async {
              final picked = await AccountPicker.show(
                context,
                accounts: accounts,
                selectedId: account?.id,
              );
              if (picked != null) onChanged(picked);
            },
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.isSelected,
    required this.onToggle,
    required this.onOpen,
  });

  final TransactionCandidate candidate;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isIncomplete =
        candidate.amount == null || candidate.transactionDate == null;
    final needsAttention = isIncomplete || candidate.isPossibleDuplicate;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      borderColor: needsAttention
          ? context.palette.warning.withValues(alpha: 0.45)
          : (isSelected
              ? context.colors.primary.withValues(alpha: 0.4)
              : null),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => onToggle(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: AppRadius.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            candidate.merchant ??
                                candidate.description ??
                                'Unnamed transaction',
                            style: context.text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        AppSpacing.hGapSm,
                        if (candidate.amount == null)
                          Text(
                            'No amount',
                            style: context.text.labelMedium
                                ?.copyWith(color: context.palette.danger),
                          )
                        else
                          MoneyText.transaction(
                            candidate.amount!,
                            transactionType: candidate.type,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              candidate.transactionDate == null
                                  ? 'No date'
                                  : DateDisplay.dayMonthYear(
                                      candidate.transactionDate!,
                                    ),
                              if (candidate.suggestedCategory != null)
                                candidate.suggestedCategory!.name,
                            ].join(' · '),
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: context.palette.textTertiary,
                        ),
                      ],
                    ),
                    if (needsAttention) ...[
                      AppSpacing.gapSm,
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          if (candidate.isPossibleDuplicate)
                            AppChipLabel(
                              label: 'Possible duplicate',
                              color: context.palette.warning,
                              icon: Icons.content_copy_outlined,
                              dense: true,
                            ),
                          if (isIncomplete)
                            AppChipLabel(
                              label: 'Needs details',
                              color: context.palette.danger,
                              icon: Icons.edit_outlined,
                              dense: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedRow extends StatelessWidget {
  const _ResolvedRow({required this.candidate});

  final TransactionCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final isConfirmed = candidate.status == OcrCandidateStatus.confirmed;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: isConfirmed && candidate.createdTransactionId != null
          ? () => context.push(
                AppRoutes.transactionDetail(candidate.createdTransactionId!),
              )
          : null,
      child: Row(
        children: [
          Icon(
            isConfirmed
                ? Icons.check_circle_outline_rounded
                : Icons.remove_circle_outline_rounded,
            size: 20,
            color: isConfirmed
                ? context.palette.income
                : context.palette.textTertiary,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.merchant ?? candidate.description ?? 'Transaction',
                  style: context.text.titleSmall?.copyWith(
                    color: isConfirmed
                        ? null
                        : context.palette.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  candidate.status.label,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          if (candidate.amount != null)
            MoneyText(
              candidate.amount!,
              size: MoneySize.row,
              color: isConfirmed ? null : context.palette.textTertiary,
            ),
        ],
      ),
    );
  }
}

class _StatementFooter extends StatelessWidget {
  const _StatementFooter({
    required this.selected,
    required this.isSubmitting,
    required this.onConfirm,
  });

  final List<TransactionCandidate> selected;
  final bool isSubmitting;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    // Only the amounts that are present can be totalled; that is the honest
    // figure, and the incomplete ones are flagged separately.
    final withAmounts = selected.where((c) => c.amount != null).toList();
    final currency =
        withAmounts.isEmpty ? 'LKR' : withAmounts.first.amount!.currency;

    var inflow = Money.zero(currency);
    var outflow = Money.zero(currency);
    for (final candidate in withAmounts) {
      if (candidate.amount!.currency != currency) continue;
      if (candidate.type == TransactionType.income) {
        inflow += candidate.amount!;
      } else {
        outflow += candidate.amount!;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.outline)),
      ),
      padding: const EdgeInsets.all(AppSpacing.page),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selected.length} selected',
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (!outflow.isZero) ...[
                            Text(
                              '-${outflow.formatCompact()}',
                              style: context.text.bodySmall
                                  ?.copyWith(color: context.palette.expense),
                            ),
                            AppSpacing.hGapSm,
                          ],
                          if (!inflow.isZero)
                            Text(
                              '+${inflow.formatCompact()}',
                              style: context.text.bodySmall
                                  ?.copyWith(color: context.palette.income),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                AppSpacing.hGapLg,
                FilledButton(
                  onPressed:
                      selected.isEmpty || isSubmitting ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
