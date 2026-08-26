import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFavKey = 'favourite_doc_ids';

class FavouritesNotifier extends StateNotifier<Set<String>> {
  FavouritesNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kFavKey) ?? [];
    state = ids.toSet();
  }

  Future<void> toggle(String docId) async {
    final next = Set<String>.from(state);
    if (next.contains(docId)) {
      next.remove(docId);
    } else {
      next.add(docId);
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFavKey, next.toList());
  }

  bool isFavourite(String docId) => state.contains(docId);
}

final favouritesProvider =
    StateNotifierProvider<FavouritesNotifier, Set<String>>(
  (ref) => FavouritesNotifier(),
);
