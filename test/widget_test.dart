import 'package:flutter_test/flutter_test.dart';
import 'package:raidrive_macos/models/remote_config.dart';
import 'package:raidrive_macos/services/mounter.dart';

void main() {
  group('parseLocalNfsMounts', () {
    test('yalnızca 127.0.0.1 NFS bağlantılarını tam yol olarak döndürür', () {
      const out = '''
127.0.0.1:/ on /Volumes/web (nfs, nodev, nosuid, mounted by kaan)
127.0.0.1:/ on /Volumes/web-2 (nfs, nodev, nosuid, mounted by kaan)
nas.local:/export on /Volumes/nas (nfs)
/dev/disk3s1 on /Volumes/web3 (apfs, local)
''';
      final points = Mounter.parseLocalNfsMounts(out);
      expect(points, {'/Volumes/web', '/Volumes/web-2'});
      expect(points.contains('/Volumes/we'), isFalse);
    });
  });

  group('classifyError', () {
    test('kimlik hatalarını tanır', () {
      expect(Mounter.classifyError('ssh: handshake failed: ssh: unable to authenticate').kind, MountErrorKind.auth);
      expect(Mounter.classifyError('530 Login incorrect.').kind, MountErrorKind.auth);
    });
    test('ağ hatalarını tanır', () {
      expect(Mounter.classifyError('dial tcp: lookup x: no such host').kind, MountErrorKind.network);
    });
  });

  test('rcloneName yeniden adlandırmadan bağımsızdır', () {
    final a = RemoteConfig(id: '17000-12', name: 'a', host: 'h', port: 22, user: 'u');
    expect(a.rcloneName, 'zd1700012');
    expect(a.copyWith(name: 'b').rcloneName, a.rcloneName);
  });
}
