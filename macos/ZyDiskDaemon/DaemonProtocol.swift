import Foundation

/// Uygulama ile root yetkili yardımcı servis (daemon) arasındaki XPC sözleşmesi.
/// Protokol değiştiğinde `ZyDiskDaemonVersion` artırılmalı; uygulama sürüm uyuşmazlığında
/// servisi otomatik günceller.
let ZyDiskDaemonVersion = "2.0.0"
let ZyDiskDaemonLabel = "com.conaksoft.zydisk.daemon"
let ZyDiskAppIdentifier = "com.conaksoft.zydisk"

@objc(ZyDiskDaemonProtocolV2)
public protocol DaemonProtocol {
    func version(withReply reply: @escaping (String) -> Void)
    func mountNFS(port: Int, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void)
    func unmount(mountPoint: String, force: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    /// Yalnızca aynı Team ID ile imzalanmış bir daemon ikilisinden kendini günceller.
    func update(fromPath path: String, withReply reply: @escaping (Bool, String?) -> Void)
    func uninstall(withReply reply: @escaping (Bool, String?) -> Void)
}
