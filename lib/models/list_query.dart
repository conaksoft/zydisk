import 'remote_config.dart';

enum StatusFilter { all, mounted, unmounted }

enum SortMode { nameAsc, nameDesc, mountedFirst, protocol, newest, oldest }

enum GroupMode { none, protocol, status, host }

extension SortModeLabel on SortMode {
  String get label {
    switch (this) {
      case SortMode.nameAsc:
        return 'Ad (A → Z)';
      case SortMode.nameDesc:
        return 'Ad (Z → A)';
      case SortMode.mountedFirst:
        return 'Önce bağlı olanlar';
      case SortMode.protocol:
        return 'Protokol';
      case SortMode.newest:
        return 'En yeni eklenen';
      case SortMode.oldest:
        return 'En eski eklenen';
    }
  }
}

extension GroupModeLabel on GroupMode {
  String get label {
    switch (this) {
      case GroupMode.none:
        return 'Gruplama yok';
      case GroupMode.protocol:
        return 'Protokole göre';
      case GroupMode.status:
        return 'Duruma göre';
      case GroupMode.host:
        return 'Sunucuya göre';
    }
  }
}

class RemoteGroup {
  final String key;
  final String title;
  final List<RemoteConfig> items;
  const RemoteGroup(this.key, this.title, this.items);
}

/// Sürücü listesi için arama + filtre + sıralama + gruplama.
class ListQuery {
  final String search;
  final StatusFilter status;
  final Set<RemoteType> types; // boşsa tüm protokoller
  final SortMode sort;
  final GroupMode group;

  const ListQuery({
    this.search = '',
    this.status = StatusFilter.all,
    this.types = const {},
    this.sort = SortMode.nameAsc,
    this.group = GroupMode.none,
  });

  bool get isFiltering => search.trim().isNotEmpty || status != StatusFilter.all || types.isNotEmpty;

  ListQuery copyWith({String? search, StatusFilter? status, Set<RemoteType>? types, SortMode? sort, GroupMode? group}) {
    return ListQuery(
      search: search ?? this.search,
      status: status ?? this.status,
      types: types ?? this.types,
      sort: sort ?? this.sort,
      group: group ?? this.group,
    );
  }

  ListQuery cleared() => ListQuery(sort: sort, group: group);

  bool matches(RemoteConfig r) {
    if (status == StatusFilter.mounted && !r.isMounted) return false;
    if (status == StatusFilter.unmounted && r.isMounted) return false;
    if (types.isNotEmpty && !types.contains(r.type)) return false;
    final terms = _fold(search).split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (terms.isEmpty) return true;
    final haystack = _fold([r.name, r.host, r.user, r.path, r.type.label, '${r.port}'].join(' '));
    return terms.every(haystack.contains);
  }

  /// [remotes] eklenme sırasındadır; "en yeni/en eski" sıralaması bu sıraya dayanır.
  List<RemoteGroup> apply(List<RemoteConfig> remotes) {
    final order = {for (var i = 0; i < remotes.length; i++) remotes[i].id: i};
    final filtered = remotes.where(matches).toList();
    filtered.sort((a, b) => _compare(a, b, order));

    if (group == GroupMode.none) {
      return [RemoteGroup('all', '', filtered)];
    }

    final groups = <String, RemoteGroup>{};
    for (final r in filtered) {
      final (key, title) = _groupOf(r);
      groups.putIfAbsent(key, () => RemoteGroup(key, title, [])).items.add(r);
    }
    final result = groups.values.toList();
    result.sort((a, b) => _groupRank(a.key).compareTo(_groupRank(b.key)) != 0
        ? _groupRank(a.key).compareTo(_groupRank(b.key))
        : _fold(a.title).compareTo(_fold(b.title)));
    return result;
  }

  int _compare(RemoteConfig a, RemoteConfig b, Map<String, int> order) {
    int byName() => _fold(a.name).compareTo(_fold(b.name));
    switch (sort) {
      case SortMode.nameAsc:
        return byName();
      case SortMode.nameDesc:
        return -byName();
      case SortMode.mountedFirst:
        final m = (b.isMounted ? 1 : 0) - (a.isMounted ? 1 : 0);
        return m != 0 ? m : byName();
      case SortMode.protocol:
        final t = a.type.index - b.type.index;
        return t != 0 ? t : byName();
      case SortMode.newest:
        return order[b.id]!.compareTo(order[a.id]!);
      case SortMode.oldest:
        return order[a.id]!.compareTo(order[b.id]!);
    }
  }

  (String, String) _groupOf(RemoteConfig r) {
    switch (group) {
      case GroupMode.protocol:
        return ('type:${r.type.index}', r.type.label);
      case GroupMode.status:
        return r.isMounted ? ('status:0', 'Bağlı') : ('status:1', 'Bağlı değil');
      case GroupMode.host:
        return ('host:${r.host.toLowerCase()}', r.host);
      case GroupMode.none:
        return ('all', '');
    }
  }

  /// Protokol ve durum grupları sabit sırada; sunucu grupları ada göre.
  int _groupRank(String key) {
    if (key.startsWith('type:') || key.startsWith('status:')) return int.parse(key.split(':').last);
    return 0;
  }

  /// Büyük/küçük harf ve Türkçe karakter farkını yok sayar (ı/i, ş/s ...).
  static String _fold(String s) {
    const map = {'ı': 'i', 'İ': 'i', 'I': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u', 'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'};
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(map[ch] ?? ch.toLowerCase());
    }
    return b.toString();
  }

  Map<String, dynamic> toPrefs() => {
        'status': status.name,
        'types': types.map((t) => t.name).toList(),
        'sort': sort.name,
        'group': group.name,
      };

  factory ListQuery.fromPrefs(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    return ListQuery(
      status: pick(StatusFilter.values, j['status'], StatusFilter.all),
      types: ((j['types'] as List?) ?? const [])
          .map((n) => RemoteType.values.where((t) => t.name == n).firstOrNull)
          .whereType<RemoteType>()
          .toSet(),
      sort: pick(SortMode.values, j['sort'], SortMode.nameAsc),
      group: pick(GroupMode.values, j['group'], GroupMode.none),
    );
  }
}
