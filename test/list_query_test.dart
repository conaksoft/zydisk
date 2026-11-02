import 'package:flutter_test/flutter_test.dart';
import 'package:raidrive_macos/models/list_query.dart';
import 'package:raidrive_macos/models/remote_config.dart';

RemoteConfig r(String id, String name, RemoteType type, {String host = 'h.com', bool mounted = false}) =>
    RemoteConfig(id: id, name: name, host: host, port: 22, user: 'u', type: type, isMounted: mounted);

void main() {
  // Eklenme sırası: web, yedek, Arsiv, ftp-site
  final remotes = [
    r('1', 'web', RemoteType.sftp, host: 'prod.example.com', mounted: true),
    r('2', 'yedek', RemoteType.s3, host: 's3.amazonaws.com'),
    r('3', 'Arsiv', RemoteType.s3, host: 's3.amazonaws.com', mounted: true),
    r('4', 'ftp-site', RemoteType.ftp, host: 'prod.example.com'),
  ];

  List<String> names(ListQuery q) => q.apply(remotes).expand((g) => g.items).map((e) => e.name).toList();

  test('arama; ad, sunucu ve protokol etiketinde, Türkçe karakter ve büyük/küçük harf duyarsız', () {
    expect(names(const ListQuery(search: 'ARŞİV')), ['Arsiv']);
    expect(names(const ListQuery(search: 'prod')), ['ftp-site', 'web']);
    expect(names(const ListQuery(search: 's3 yed')), ['yedek']);
  });

  test('durum ve protokol filtresi', () {
    expect(names(const ListQuery(status: StatusFilter.mounted)), ['Arsiv', 'web']);
    expect(names(const ListQuery(types: {RemoteType.s3}, status: StatusFilter.unmounted)), ['yedek']);
  });

  test('sıralama', () {
    expect(names(const ListQuery(sort: SortMode.nameDesc)), ['yedek', 'web', 'ftp-site', 'Arsiv']);
    expect(names(const ListQuery(sort: SortMode.mountedFirst)), ['Arsiv', 'web', 'ftp-site', 'yedek']);
    expect(names(const ListQuery(sort: SortMode.newest)), ['ftp-site', 'Arsiv', 'yedek', 'web']);
  });

  test('gruplama', () {
    final byType = const ListQuery(group: GroupMode.protocol).apply(remotes);
    expect(byType.map((g) => g.title), ['SFTP / SSH', 'FTP', 'S3 Compatible']);
    final byStatus = const ListQuery(group: GroupMode.status).apply(remotes);
    expect(byStatus.map((g) => '${g.title}:${g.items.length}'), ['Bağlı:2', 'Bağlı değil:2']);
    final byHost = const ListQuery(group: GroupMode.host).apply(remotes);
    expect(byHost.map((g) => g.title), ['prod.example.com', 's3.amazonaws.com']);
  });

  test('tercihler kaydedilip geri yüklenir (arama hariç)', () {
    const q = ListQuery(
        search: 'x', status: StatusFilter.mounted, types: {RemoteType.ftp}, sort: SortMode.oldest, group: GroupMode.host);
    final back = ListQuery.fromPrefs(q.toPrefs());
    expect(back.search, '');
    expect(back.status, StatusFilter.mounted);
    expect(back.types, {RemoteType.ftp});
    expect(back.sort, SortMode.oldest);
    expect(back.group, GroupMode.host);
  });
}
