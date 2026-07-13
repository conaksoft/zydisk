import Foundation

@objc(DaemonProtocol)
public protocol DaemonProtocol {
    func mountNFS(port: Int, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void)
    func unmount(mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void)
}
