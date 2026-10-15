import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/document.dart';
import '../../../shared/models/transaction_candidate.dart';
import '../../../shared/providers/account_providers.dart';
import '../../../shared/providers/ocr_providers.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/pickers.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/transaction_tile.dart';
import 'statement_review_screen.dart';
import 'widgets/confidence_field.dart';
import 'widgets/document_preview.dart';

/// Review one extracted transaction before it becomes real.
///
/// Every field is editable, every field shows how confident the parser was, and
/// the Confirm button is disabled until the values a transaction cannot exist
/// without — amount, account, date — are present. The database enforces the same
/// three, so this screen is the courteous version of a rule that holds anyway.
class OcrReviewScreen extends ConsumerStatefulWidget {
  const OcrReviewScreen({
    super.key,
    required this.candidate,
    required this.document,
    this.position,
    this.total,
    this.onConfirmed,
  });

  final TransactionCandidate candidate;
  final FinoraDocument? document;

  /// `2 of 5`, when reviewing a statement's rows one at a time.
  final int? position;
  final int? total;
  final VoidCallback? onConfirmed;

  @override
  ConsumerState<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends ConsumerState<OcrReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _merchantController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _referenceController;
  final _notesController = TextEditingController();

  late TransactionType _type;
  Account? _account;
  Category? _category;
  PaymentMethod? _paymentMethod;
  late DateTime _date;
  bool _attachDocument = true;
  bool _isSubmitting = false;
  bool _duplicateAcknowledged = false;

  TransactionCandidate get _candidate => widget.candidate;

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController(
      text: _candidate.amount?.toEditableString() ?? '',
    );
    _merchantController = TextEditingController(text: _candidate.merchant ?? '');
    _descriptionController =
        TextEditingController(text: _candidate.description ?? '');
    _referenceController =
        TextEditingController(text: _candidate.referenceNumber ?? '');

    _type = _candidate.type;
    _paymentMethod = _candidate.paymentMethod;
    // A missing date defaults to today only as a starting value for the picker;
    // the field still reads as "not detected" and must be confirmed.
    _date = _candidate.transactionDate ?? DateTime.now();

    // The parser never guesses an account, so the user's default is offered as a
    // convenience — but it is a real choice they can see and change.
    _account = ref.read(accountByIdProvider(_candidate.accountId)) ??
        ref.read(defaultAccountProvider);
    _category = ref.read(categoryByIdProvider(_candidate.suggestedCategoryId));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _descriptionController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Money? get _amount {
    final String currency =
        _account?.currency ?? _candidate.currency;
    return Money.tryParse(_amountController.text, currency);
  }

  /// What still stands between this candidate and a transaction.
  ///
  /// Recomputed from the *edited* values rather than read off the candidate, so
  /// filling in a missing amount clears its warning immediately.
  List<CandidateWarning> get _liveWarnings {
    final warnings = <CandidateWarning>[];
    final amount = _amount;

    if (amount == null || amount.isZero) {
      warnings.add(const CandidateWarning(
        CandidateField.amount,
        'Amount needed',
        'Enter the transaction amount.',
        blocking: true,
      ));
    } else if (_candidate.needsVerification(CandidateField.amount) &&
        amount == _candidate.amount) {
      warnings.add(const CandidateWarning(
        CandidateField.amount,
        'Amount unclear',
        'Check the amount against the document.',
      ));
    }

    if (_account == null) {
      warnings.add(const CandidateWarning(
        CandidateField.merchant,
        'Account needed',
        'Choose which account this belongs to.',
        blocking: true,
      ));
    }

    if (_candidate.transactionDate == null) {
      warnings.add(const CandidateWarning(
        CandidateField.date,
        'Date not detected',
        'Check the date is right before saving.',
      ));
    } else if (_candidate.needsVerification(CandidateField.date) &&
        AppDateUtils.isSameDay(_date, _candidate.transactionDate!)) {
      warnings.add(const CandidateWarning(
        CandidateField.date,
        'Date unclear',
        'The day and month order could not be determined with certainty.',
      ));
    }

    if (_merchantController.text.trim().isEmpty &&
        _descriptionController.text.trim().isEmpty) {
      warnings.add(const CandidateWarning(
        CandidateField.merchant,
        'No merchant or description',
        'Add one so you can recognise this later.',
      ));
    }

    if (_category == null && !_type.isTransfer) {
      warnings.add(const CandidateWarning(
        CandidateField.category,
        'No category',
        'Choose one to keep your reports accurate.',
      ));
    }

    return warnings;
  }

  bool get _canConfirm => !_liveWarnings.any((w) => w.blocking);

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final account = _account;
    final amount = _amount;
    if (account == null || amount == null || amount.isZero) return;

    context.hideKeyboard();
    setState(() => _isSubmitting = true);

    try {
      await ref.read(importControllerProvider.notifier).confirm(
            candidate: _candidate,
            accountId: account.id,
            amount: amount,
            date: _date,
            type: _type,
            categoryId: _category?.id,
            merchant: _nullIfEmpty(_merchantController.text),
            description: _nullIfEmpty(_descriptionController.text),
            paymentMethod: _paymentMethod,
            referenceNumber: _nullIfEmpty(_referenceController.text),
            notes: _nullIfEmpty(_notesController.text),
            attachDocument: _attachDocument,
          );

      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Transaction saved');

      if (widget.onConfirmed != null) {
        widget.onConfirmed!();
      } else {
        context.go(AppRoutes.transactions);
      }
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Keeps the edits without creating a transaction.
  Future<void> _saveDraft() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(importControllerProvider.notifier).saveDraft(
            _candidate.copyWith(
              type: _type,
              amount: _amount,
              merchant: _nullIfEmpty(_merchantController.text),
              description: _nullIfEmpty(_descriptionController.text),
              transactionDate: _date,
              suggestedCategoryId: _category?.id,
              paymentMethod: _paymentMethod,
              referenceNumber: _nullIfEmpty(_referenceController.text),
              accountId: _account?.id,
            ),
          );

      if (!mounted) return;
      AppFeedback.showSuccess(
        context,
        'Saved for later — nothing has been added to your transactions yet',
      );
      if (widget.onConfirmed != null) {
        widget.onConfirmed!();
      } else {
        context.pop();
      }
    } on Object catch (error) {
      if (mounted) AppFeedback.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _ignore() async {
    final confirmed = await AppFeedback.confirm(
      context,
      title: 'Skip this transaction?',
      message: 'It will not be added. You can still see it in your import '
          'history.',
      confirmLabel: 'Skip',
    );
    if (!confirmed || !mounted) return;

    await ref.read(importControllerProvider.notifier).ignore(_candidate);
    if (!mounted) return;

    if (widget.onConfirmed != null) {
      widget.onConfirmed!();
    } else {
      context.pop();
    }
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activeAccountsProvider);
    final categories = ref.watch(
      categoriesByKindProvider(
        _type == TransactionType.income
            ? CategoryKind.income
            : CategoryKind.expense,
      ),
    );
    final String currency = _account?.currency ?? _candidate.currency;
    final duplicates = ref.watch(candidateDuplicatesProvider(_candidate));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.position == null
              ? 'Review transaction'
              : 'Review ${widget.position} of ${widget.total}',
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _ignore,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              Text(
                'Review extracted transaction',
                style: context.text.titleLarge,
              ),
              AppSpacing.gapXs,
              Text(
                'Check the details against the document, then confirm. Nothing '
                'is saved until you do.',
                style: context.text.bodySmall,
              ),
              AppSpacing.gapLg,

              if (widget.document != null) ...[
                DocumentPreview(
                  document: widget.document!,
                  onTap: () => DocumentViewerScreen.open(
                    context,
                    document: widget.document!,
                  ),
                ),
                AppSpacing.gapLg,
              ],

              CandidateWarnings(warnings: _liveWarnings),
              AppSpacing.gapLg,

              // Duplicate detection is advisory: it surfaces the match and lets
              // the user decide. Automatically skipping someone's transaction
              // would be the wrong call to make for them.
              duplicates.maybeWhen(
                data: (matches) => matches.isEmpty || _duplicateAcknowledged
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: _DuplicateCard(
                          matches: matches,
                          onSkip: _ignore,
                          onCreateAnyway: () =>
                              setState(() => _duplicateAcknowledged = true),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

              SegmentedTypeSelector<TransactionType>(
                options: const [
                  TransactionType.expense,
                  TransactionType.income,
                ],
                selected: _type == TransactionType.transfer
                    ? TransactionType.expense
                    : _type,
                labelFor: (type) => type.label,
                iconFor: (type) => type == TransactionType.income
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                colorFor: (type) => type == TransactionType.income
                    ? context.palette.income
                    : context.palette.expense,
                onChanged: (type) => setState(() {
                  _type = type;
                  _category = null;
                }),
              ),
              AppSpacing.gapXl,

              ReviewField(
                label: 'Amount',
                isRequired: true,
                level: confidenceLevelFor(
                  _candidate.confidenceFor(CandidateField.amount),
                  hasValue: _candidate.amount != null,
                ),
                score: _candidate.confidenceFor(CandidateField.amount),
                rawText: _candidate.rawLine,
                child: AmountField(
                  controller: _amountController,
                  currency: currency,
                  label: 'Amount',
                  autofocus: _candidate.amount == null,
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      Validators.amount(value, currency: currency),
                ),
              ),

              ReviewField(
                label: 'Account',
                isRequired: true,
                // The parser deliberately never guesses this, so it is always
                // presented as the user's decision rather than a correction.
                level: _account == null
                    ? ConfidenceLevel.missing
                    : ConfidenceLevel.high,
                child: PickerField(
                  label: 'Account',
                  value: _account?.name,
                  leading: _account == null
                      ? null
                      : IconBadge(
                          icon: _account!.icon,
                          color: _account!.color,
                          size: 24,
                          iconSize: 14,
                        ),
                  onTap: () async {
                    final picked = await AccountPicker.show(
                      context,
                      accounts: accounts,
                      selectedId: _account?.id,
                    );
                    if (picked != null) setState(() => _account = picked);
                  },
                ),
              ),

              ReviewField(
                label: 'Date',
                isRequired: true,
                level: confidenceLevelFor(
                  _candidate.confidenceFor(CandidateField.date),
                  hasValue: _candidate.transactionDate != null,
                ),
                score: _candidate.confidenceFor(CandidateField.date),
                child: PickerField(
                  label: 'Date',
                  value: DateDisplay.dayMonthYear(_date),
                  leading: const Icon(Icons.event_outlined, size: 20),
                  onTap: () async {
                    final picked = await DateTimePickers.pickTransactionDate(
                      context,
                      initial: _date,
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ),

              ReviewField(
                label: 'Merchant',
                level: confidenceLevelFor(
                  _candidate.confidenceFor(CandidateField.merchant),
                  hasValue: _candidate.merchant != null,
                ),
                score: _candidate.confidenceFor(CandidateField.merchant),
                child: TextFormField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Merchant',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
              ),

              ReviewField(
                label: 'Category',
                level: confidenceLevelFor(
                  _candidate.confidenceFor(CandidateField.category),
                  hasValue: _category != null,
                ),
                score: _candidate.confidenceFor(CandidateField.category),
                child: PickerField(
                  label: 'Category',
                  value: _category?.name,
                  leading: _category == null
                      ? null
                      : Icon(
                          _category!.icon,
                          size: 20,
                          color: _category!.color,
                        ),
                  onTap: () async {
                    final picked = await CategoryPicker.show(
                      context,
                      categories: categories,
                      selectedId: _category?.id,
                      allowNone: true,
                    );
                    if (picked != null) {
                      setState(() => _category =
                          CategoryPicker.isNone(picked) ? null : picked);
                    }
                  },
                ),
              ),

              ReviewField(
                label: 'Payment method',
                level: confidenceLevelFor(
                  _candidate.confidenceFor(CandidateField.paymentMethod),
                  hasValue: _paymentMethod != null,
                ),
                score: _candidate.confidenceFor(CandidateField.paymentMethod),
                child: PickerField(
                  label: 'Payment method',
                  value: _paymentMethod?.label,
                  placeholder: 'Not detected',
                  leading: _paymentMethod == null
                      ? null
                      : Icon(
                          PaymentMethodPicker.iconFor(_paymentMethod!),
                          size: 20,
                        ),
                  onTap: () async {
                    final picked = await PaymentMethodPicker.show(
                      context,
                      selected: _paymentMethod,
                    );
                    if (picked != null) {
                      setState(() => _paymentMethod = picked);
                    }
                  },
                ),
              ),

              ReviewField(
                label: 'Description',
                level: _candidate.description == null
                    ? ConfidenceLevel.missing
                    : ConfidenceLevel.high,
                child: TextFormField(
                  controller: _descriptionController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ),

              if (_candidate.referenceNumber != null)
                ReviewField(
                  label: 'Reference',
                  level: confidenceLevelFor(
                    _candidate.confidenceFor(CandidateField.reference),
                    hasValue: true,
                  ),
                  score: _candidate.confidenceFor(CandidateField.reference),
                  child: TextFormField(
                    controller: _referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference number',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                ),

              AppSpacing.gapSm,
              AppCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _attachDocument,
                  onChanged: (value) =>
                      setState(() => _attachDocument = value),
                  title: Text(
                    'Attach the document',
                    style: context.text.titleSmall,
                  ),
                  subtitle: Text(
                    'Keeps the original with the transaction as evidence',
                    style: context.text.bodySmall,
                  ),
                ),
              ),
              AppSpacing.gapLg,

              if (widget.document != null)
                RawTextPanel(documentId: widget.document!.id),

              AppSpacing.gapXxl,
              _ConfirmBar(
                canConfirm: _canConfirm,
                isSubmitting: _isSubmitting,
                onConfirm: _confirm,
                onSaveDraft: _saveDraft,
                onCancel: () => context.pop(),
              ),
              AppSpacing.gapXl,
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.canConfirm,
    required this.isSubmitting,
    required this.onConfirm,
    required this.onSaveDraft,
    required this.onCancel,
  });

  final bool canConfirm;
  final bool isSubmitting;
  final VoidCallback onConfirm;
  final VoidCallback onSaveDraft;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          // Disabled rather than failing on tap: the database refuses a
          // candidate with no amount, account or date, so offering the button
          // would only produce an error the user could have been spared.
          onPressed: canConfirm && !isSubmitting ? onConfirm : null,
          icon: isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(isSubmitting ? 'Saving…' : 'Confirm transaction'),
        ),
        if (!canConfirm) ...[
          AppSpacing.gapSm,
          Text(
            'Fill in the details marked above to continue.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall
                ?.copyWith(color: context.palette.warning),
          ),
        ],
        AppSpacing.gapSm,
        OutlinedButton(
          onPressed: isSubmitting ? null : onSaveDraft,
          child: const Text('Save as draft'),
        ),
        AppSpacing.gapSm,
        TextButton(
          onPressed: isSubmitting ? null : onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// A possible duplicate, with the three choices the user actually has.
class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.matches,
    required this.onSkip,
    required this.onCreateAnyway,
  });

  final List<DuplicateMatch> matches;
  final VoidCallback onSkip;
  final VoidCallback onCreateAnyway;

  @override
  Widget build(BuildContext context) {
    final strongest = matches.first;

    return AppCard(
      borderColor: context.palette.warning.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.content_copy_outlined,
                size: 18,
                color: context.palette.warning,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  'Possible duplicate',
                  style: context.text.titleSmall
                      ?.copyWith(color: context.palette.warning),
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            'A similar transaction already exists.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapMd,
          TransactionMiniTile(
            transaction: strongest.existing,
            onTap: () => context.push(
              AppRoutes.transactionDetail(strongest.existing.id),
            ),
          ),
          if (strongest.reasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.page,
                top: AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final reason in strongest.reasons)
                    AppChipLabel(label: reason, dense: true),
                ],
              ),
            ),
          AppSpacing.gapMd,
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: FilledButton(
                  onPressed: onCreateAnyway,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                  ),
                  child: const Text('Not a duplicate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loads a job and routes to the right review experience.
///
/// A receipt gets the single-transaction form; a statement gets the selectable
/// list, because reviewing twelve rows one modal at a time would be miserable.
class OcrReviewEntryScreen extends ConsumerStatefulWidget {
  const OcrReviewEntryScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<OcrReviewEntryScreen> createState() =>
      _OcrReviewEntryScreenState();
}

class _OcrReviewEntryScreenState extends ConsumerState<OcrReviewEntryScreen> {
  @override
  void initState() {
    super.initState();

    // Loaded once, in initState rather than during build. Kicking this off from
    // build would re-fire on every rebuild, and each call replaces the
    // controller's state — so a rebuild mid-edit would discard the user's
    // changes.
    final state = ref.read(importControllerProvider);
    if (state.job?.id != widget.jobId) {
      Future.microtask(() {
        if (mounted) {
          ref.read(importControllerProvider.notifier).loadJob(widget.jobId);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);

    if (state.stage == ImportStage.failed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: ErrorStateView(
          error: state.failure ?? Exception('Could not open this import'),
          onRetry: () =>
              ref.read(importControllerProvider.notifier).loadJob(widget.jobId),
        ),
      );
    }

    // Still loading, or loaded a different job.
    if (state.job?.id != widget.jobId) {
      return const Scaffold(body: LoadingView(message: 'Opening review…'));
    }

    if (state.candidates.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nothing to review',
          message: 'This import produced no transactions.',
        ),
      );
    }

    return _routeFor(context, state);
  }

  Widget _routeFor(BuildContext context, ImportState state) {
    final pending = state.pendingCandidates;

    if (pending.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'All done',
          message: 'Every transaction from this document has been dealt with.',
          actionLabel: 'View transactions',
          onAction: () => context.go(AppRoutes.transactions),
        ),
      );
    }

    if (state.isMultiTransaction) {
      return StatementReviewScreen(jobId: widget.jobId);
    }

    return OcrReviewScreen(
      candidate: pending.first,
      document: state.document,
    );
  }
}
