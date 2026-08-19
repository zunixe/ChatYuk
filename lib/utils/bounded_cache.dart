/// Cache FIFO dengan batas kapasitas — evict entry tertua saat penuh.
/// Dipakai untuk bytes avatar hasil decode base64 (online_users & nearby).
class BoundedCache<K, V> {
  BoundedCache(this.maxSize);

  final int maxSize;
  final Map<K, V> _map = {};
  final List<K> _order = [];

  V? get(K key) {
    final i = _order.indexOf(key);
    if (i >= 0) {
      _order.removeAt(i);
      _order.add(key);
    }
    return _map[key];
  }

  V putIfAbsent(K key, V Function() ifAbsent) {
    final existing = _map[key];
    if (existing != null) return existing;
    if (_order.length >= maxSize) _map.remove(_order.removeAt(0));
    final val = ifAbsent();
    _map[key] = val;
    _order.add(key);
    return val;
  }

  void clear() {
    _map.clear();
    _order.clear();
  }
}
