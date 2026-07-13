import Foundation

@objc protocol DaemonProtocol {
    func mountNFS(port: Int, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void)
    func unmount(mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void)
}

let connection = NSXPCConnection(machServiceName: "com.conaksoft.zydisk.daemon", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: DaemonProtocol.self)
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("XPC Error: \(error)")
    exit(1)
} as! DaemonProtocol

print("Sending XPC mountNFS...")
proxy.mountNFS(port: 40794, mountPoint: "/Volumes/OTO3DPARCA") { success, error in
    print("Reply received! success: \(success), error: \(String(describing: error))")
    exit(0)
}

RunLoop.main.run()

