import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/enums.dart';
import '../../core/errors/app_exception.dart';
import '../../core/services/firebase_service.dart';
import '../models/category.dart';
import '../models/json_map.dart';
import 'base_repository.dart';
import 'relation_loader.dart';

/// Categories, at `users/{uid}/categories`.
///
/// The default set is written by the `onUserCreate` Cloud Function, not by the
/// app on first launch. Two devices signing in at once would otherwise each
/// seed a full set and the user would see every category twice.
class CategoryRepository extends BaseRepository {
  CategoryRepository({super.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseService.categories(userId);

  Future<List<Category>> fetchAll({bool includeArchived = false}) async {
    List<Category> categories;
    try {
      categories = await fetchList(
        _col.orderBy('kind').orderBy('sort_order').orderBy('name'),
        Category.fromJson,
      );
    } catch (_) {
      categories = await fetchList(_col, Category.fromJson);
      categories.sort((a, b) {
        final kindCmp = a.kind.index.compareTo(b.kind.index);
        if (kindCmp != 0) return kindCmp;
        final sortCmp = a.sortOrder.compareTo(b.sortOrder);
        if (sortCmp != 0) return sortCmp;
        return a.name.compareTo(b.name);
      });
    }
    if (includeArchived) return categories;
    return categories.where((c) => !c.isArchived).toList(growable: false);
  }

  /// Filters in memory rather than adding a `where` clause.
  ///
  /// The full list is a few dozen documents and every caller already needs it, so
  /// a second query would be a second billed read of data the client has.
  Future<List<Category>> fetchByKind(
    CategoryKind kind, {
    bool includeArchived = false,
  }) async {
    final all = await fetchAll(includeArchived: includeArchived);
    return all.where((c) => c.kind == kind).toList(growable: false);
  }

  Future<Category> fetchById(String id) =>
      fetchDoc(_col.doc(id), Category.fromJson);

  Future<Category> create(Category category) => guard(() async {
        final ref = _col.doc();
        await ref.set({
          ...category.toInsertJson(),
          'user_id': userId,
          'is_system': false,
          ...createdFields(),
        });
        // So the new category resolves by name in the same breath — the OCR
        // candidate mapper looks it up through the shared lookup.
        RelationLoader.invalidate();
        return fetchById(ref.id);
      });

  Future<Category> update(Category category) => guard(() async {
        await _col.doc(category.id).update({
          ...category.toUpdateJson(),
          ...updatedFields(),
        });
        RelationLoader.invalidate();
        return fetchById(category.id);
      });

  Future<Category> setArchived(String id, {required bool archived}) =>
      guard(() async {
        await _col.doc(id).update({
          'is_archived': archived,
          ...updatedFields(),
        });
        RelationLoader.invalidate();
        return fetchById(id);
      });

  /// Deletes a category, but only when nothing references it.
  ///
  /// Archiving is the normal path. Firestore enforces no referential integrity at
  /// all, so this check is the only thing standing between a delete and a history
  /// of transactions pointing at a category that no longer exists — reports would
  /// quietly lose a slice. Rewriting the user's past spending to make a delete
  /// possible would be the wrong fix.
  Future<void> delete(String id) => guard(() async {
        final category = await fetchById(id);
        if (category.isSystem) {
          throw const ValidationException(
            'Default categories cannot be deleted. Archive it instead so it '
            'stops appearing when you add a transaction.',
          );
        }

        final usage = await usageCount(id);
        if (usage > 0) {
          throw ValidationException(
            'This category is used by $usage transaction'
            '${usage == 1 ? '' : 's'}. Archive it instead so your reports stay '
            'accurate.',
          );
        }

        await _col.doc(id).delete();
        RelationLoader.invalidate();
      });

  /// How many transactions and split lines reference a category.
  ///
  /// The split count is a collection-group query: splits live under each
  /// transaction, so there is no single collection to scan. It is scoped by
  /// `user_id` because a collection group spans every user's documents, and the
  /// rules require that filter rather than trusting it.
  Future<int> usageCount(String categoryId) => guard(() async {
        final transactions = await countOf(
          FirebaseService.transactions(userId)
              .where('category_id', isEqualTo: categoryId),
        );

        final splits = await countOf(
          db
              .collectionGroup(Paths.splits)
              .where('user_id', isEqualTo: userId)
              .where('category_id', isEqualTo: categoryId),
        );

        return transactions + splits;
      });

  Future<void> reorder(List<String> orderedIds) => guard(() async {
        final batch = db.batch();
        for (var index = 0; index < orderedIds.length; index++) {
          batch.update(_col.doc(orderedIds[index]), {
            'sort_order': index,
            ...updatedFields(),
          });
        }
        await batch.commit();
      });

  /// Finds a category by name, used when mapping an OCR suggestion.
  static Category? findByName(
    List<Category> categories,
    String? name,
    CategoryKind kind,
  ) {
    if (name == null || name.isEmpty) return null;
    final needle = name.toLowerCase().trim();
    for (final category in categories) {
      if (category.kind == kind &&
          category.name.toLowerCase().trim() == needle) {
        return category;
      }
    }
    return null;
  }
}
