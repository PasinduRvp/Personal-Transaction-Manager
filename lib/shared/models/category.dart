import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_colors.dart';
import 'json_map.dart';

/// A row of `public.categories`.
///
/// Categories are never hard-deleted once a transaction references them —
/// deleting would rewrite the user's financial history. They are archived
/// instead, which hides them from pickers while keeping past transactions
/// readable.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.kind,
    this.iconName,
    this.colorHex,
    this.parentId,
    this.isSystem = false,
    this.isArchived = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final CategoryKind kind;
  final String? iconName;
  final String? colorHex;

  /// Optional parent for sub-categories (e.g. Food → Groceries).
  final String? parentId;

  /// True for the defaults seeded on sign-up. System categories can be renamed
  /// and recoloured but not deleted.
  final bool isSystem;
  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isExpense => kind == CategoryKind.expense;
  bool get isIncome => kind == CategoryKind.income;

  Color get color =>
      AppColors.tryParseHex(colorHex) ?? AppColors.deterministic(id);

  IconData get icon => CategoryIcons.resolve(iconName, kind);

  factory Category.fromJson(Json json) => Category(
        id: json.str('id'),
        userId: json.str('user_id'),
        name: json.str('name'),
        kind: CategoryKind.fromWire(json.strOrNull('kind')),
        iconName: json.strOrNull('icon'),
        colorHex: json.strOrNull('color'),
        parentId: json.strOrNull('parent_id'),
        isSystem: json.boolVal('is_system'),
        isArchived: json.boolVal('is_archived'),
        sortOrder: json.intVal('sort_order'),
        createdAt: json.dateVal('created_at'),
        updatedAt: json.dateVal('updated_at'),
      );

  Json toInsertJson() => compactJson({
        'name': name,
        'kind': kind.wire,
        'icon': iconName,
        'color': colorHex,
        'parent_id': parentId,
        'sort_order': sortOrder,
      });

  Json toUpdateJson() => compactJson({
        'name': name,
        'icon': iconName,
        'color': colorHex,
        'parent_id': parentId,
        'is_archived': isArchived,
        'sort_order': sortOrder,
      });

  Category copyWith({
    String? name,
    CategoryKind? kind,
    Object? iconName = _sentinel,
    Object? colorHex = _sentinel,
    Object? parentId = _sentinel,
    bool? isArchived,
    int? sortOrder,
  }) =>
      Category(
        id: id,
        userId: userId,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        iconName: iconName == _sentinel ? this.iconName : iconName as String?,
        colorHex: colorHex == _sentinel ? this.colorHex : colorHex as String?,
        parentId: parentId == _sentinel ? this.parentId : parentId as String?,
        isSystem: isSystem,
        isArchived: isArchived ?? this.isArchived,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static const Object _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        name,
        kind,
        iconName,
        colorHex,
        parentId,
        isSystem,
        isArchived,
        sortOrder,
      ];
}

/// Maps the icon name stored in the database to a Material icon.
///
/// Storing a name rather than a code point means the database stays readable
/// and the app can change its icon set without a migration.
class CategoryIcons {
  const CategoryIcons._();

  static const Map<String, IconData> catalogue = {
    'food': Icons.restaurant_outlined,
    'groceries': Icons.local_grocery_store_outlined,
    'transport': Icons.directions_bus_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'entertainment': Icons.movie_outlined,
    'bills': Icons.receipt_long_outlined,
    'utilities': Icons.bolt_outlined,
    'rent': Icons.home_outlined,
    'education': Icons.school_outlined,
    'healthcare': Icons.local_hospital_outlined,
    'travel': Icons.flight_outlined,
    'subscriptions': Icons.subscriptions_outlined,
    'insurance': Icons.shield_outlined,
    'personal_care': Icons.spa_outlined,
    'household': Icons.chair_outlined,
    'gifts': Icons.card_giftcard_outlined,
    'pets': Icons.pets_outlined,
    'sports': Icons.fitness_center_outlined,
    'taxes': Icons.account_balance_outlined,
    'charity': Icons.volunteer_activism_outlined,
    'salary': Icons.payments_outlined,
    'freelance': Icons.work_outline,
    'business': Icons.storefront_outlined,
    'investment': Icons.trending_up_outlined,
    'interest': Icons.percent_outlined,
    'refund': Icons.replay_outlined,
    'gift': Icons.redeem_outlined,
    'other': Icons.category_outlined,
    'transfer': Icons.swap_horiz_outlined,
    'savings': Icons.savings_outlined,
  };

  static IconData resolve(String? name, [CategoryKind? kind]) {
    if (name != null) {
      final match = catalogue[name.toLowerCase()];
      if (match != null) return match;
    }
    return kind == CategoryKind.income
        ? Icons.arrow_downward_rounded
        : Icons.category_outlined;
  }

  /// Names offered in the icon picker, in display order.
  static List<String> get pickerNames => catalogue.keys.toList();
}
