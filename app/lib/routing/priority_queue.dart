// Minimal binary min-heap for the routing module. We avoid pulling in
// `package:collection` so the routing layer has zero non-flutter, non-core
// dependencies — which is also what `flutter analyze` enforces here
// (depend_on_referenced_packages would warn otherwise).
//
// Comparator returns < 0 if `a` should be removed before `b`. Behavior
// matches `package:collection` PriorityQueue<T>.add / .removeFirst, scoped to
// what A* and Yen actually use.

class MinHeap<T> {
  MinHeap(this._compare);

  final int Function(T a, T b) _compare;
  final List<T> _data = <T>[];

  int get length => _data.length;
  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  void add(T value) {
    _data.add(value);
    _siftUp(_data.length - 1);
  }

  /// Returns and removes the smallest element. Throws StateError if empty.
  T removeMin() {
    if (_data.isEmpty) {
      throw StateError('MinHeap is empty');
    }
    final T top = _data[0];
    final T last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _siftDown(0);
    }
    return top;
  }

  T peek() {
    if (_data.isEmpty) {
      throw StateError('MinHeap is empty');
    }
    return _data[0];
  }

  void _siftUp(int idx) {
    while (idx > 0) {
      final int parent = (idx - 1) >> 1;
      if (_compare(_data[idx], _data[parent]) < 0) {
        final T tmp = _data[idx];
        _data[idx] = _data[parent];
        _data[parent] = tmp;
        idx = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int idx) {
    final int n = _data.length;
    while (true) {
      final int left = idx * 2 + 1;
      final int right = left + 1;
      int smallest = idx;
      if (left < n && _compare(_data[left], _data[smallest]) < 0) {
        smallest = left;
      }
      if (right < n && _compare(_data[right], _data[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == idx) return;
      final T tmp = _data[idx];
      _data[idx] = _data[smallest];
      _data[smallest] = tmp;
      idx = smallest;
    }
  }
}
