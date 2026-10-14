enum RemoteType { sftp, ftp, ftps, s3 }

enum AuthMethod { password, keyFile }

extension RemoteTypeExt on RemoteType {
  String get label {
    switch (this) {
      case RemoteType.sftp:
        return 'SFTP / SSH';
      case RemoteType.ftp:
        return 'FTP';
      case RemoteType.ftps:
        return 'FTPS';
      case RemoteType.s3:
        return 'S3 Compatible';
    }
  }

  String get rcloneType {
    switch (this) {
      case RemoteType.sftp:
        return 'sftp';
      case RemoteType.ftp:
      case RemoteType.ftps:
        return 'ftp';
      case RemoteType.s3:
        return 's3';
    }
  }

  String get icon {
    switch (this) {
      case RemoteType.sftp:
        return '🔐';
      case RemoteType.ftp:
        return '📁';
      case RemoteType.ftps:
        return '🔒';
      case RemoteType.s3:
        return '☁️';
    }
  }
}

class RemoteConfig {
  final String id;
  String name;
  String host;
  int port;
  String user;
  String path;
  RemoteType type;
  AuthMethod authMethod;
  String? keyFilePath;
  /// Uygulama açılışında otomatik bağlansın mı?
  bool autoMount;
  // password is stored in keychain — not here
  bool isMounted;
  String? mountPoint;

  RemoteConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    this.path = '/',
    this.type = RemoteType.sftp,
    this.authMethod = AuthMethod.password,
    this.keyFilePath,
    this.autoMount = false,
    this.isMounted = false,
    this.mountPoint,
  });

  /// rclone'a verilen dahili uzak ad (kullanıcının gördüğü addan bağımsız, yeniden adlandırmaya dayanıklı).
  String get rcloneName => 'zd${id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';

  String get endpointLabel {
    switch (type) {
      case RemoteType.s3:
        return '$host${path == '/' ? '' : path}';
      default:
        return '$user@$host:$port${path == '/' ? '' : path}';
    }
  }

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      user: json['user'] as String,
      path: json['path'] as String? ?? '/',
      type: RemoteType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RemoteType.sftp,
      ),
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
      keyFilePath: json['keyFilePath'] as String?,
      autoMount: json['autoMount'] as bool? ?? false,
      isMounted: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        'path': path,
        'type': type.name,
        'authMethod': authMethod.name,
        'keyFilePath': keyFilePath,
        'autoMount': autoMount,
      };

  RemoteConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? user,
    String? path,
    RemoteType? type,
    AuthMethod? authMethod,
    String? keyFilePath,
    bool? autoMount,
    bool? isMounted,
    String? mountPoint,
  }) {
    return RemoteConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      path: path ?? this.path,
      type: type ?? this.type,
      authMethod: authMethod ?? this.authMethod,
      keyFilePath: keyFilePath ?? this.keyFilePath,
      autoMount: autoMount ?? this.autoMount,
      isMounted: isMounted ?? this.isMounted,
      mountPoint: mountPoint ?? this.mountPoint,
    );
  }
}
