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
    this.isMounted = false,
    this.mountPoint,
  });

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
      isMounted: isMounted ?? this.isMounted,
      mountPoint: mountPoint ?? this.mountPoint,
    );
  }
}
