import 'dart:math';

/// No-repeat random selection until bag is exhausted; then reshuffle.
class ShuffleBag<T> {
  final Random _rng = Random();
  List<T> _bag = [];
  int _idx = 0;

  T next(List<T> selection) {
    if (_bag.isEmpty) {
      _bag = List.of(selection)..shuffle(_rng);
      _idx = 0;
    }
    final item = _bag[_idx];
    _idx++;
    if (_idx >= _bag.length) {
      _bag = [];
      _idx = 0;
    }
    return item;
  }

  Map<String, dynamic> toJson(Map<T, String> toKey) => {
    'bag': _bag.map((e) => toKey[e]).toList(),
    'idx': _idx,
  };
}
