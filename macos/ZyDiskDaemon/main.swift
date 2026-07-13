import Foundation

class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: DaemonProtocol.self)
        newConnection.exportedObject = Daemon()
        newConnection.resume()
        return true
    }
}

@objc class Daemon: NSObject, DaemonProtocol {
    func mountNFS(port: Int, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let mountCmd = "mount_nfs -o vers=3,nolocks,resvport,port=\(port),mountport=\(port),soft 127.0.0.1:/ \"\(mountPoint)\""
        
        var combinedCmd: String
        let dir = URL(fileURLWithPath: mountPoint)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: mountPoint, isDirectory: &isDir) {
            combinedCmd = mountCmd
        } else {
            combinedCmd = "mkdir -p \"\(mountPoint)\" && chmod 755 \"\(mountPoint)\" && \(mountCmd)"
        }
        
        let result = runCommand(cmd: combinedCmd)
        reply(result.0, result.1)
    }
    
    func unmount(mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let combinedCmd = "umount \"\(mountPoint)\" || umount -f \"\(mountPoint)\" ; sleep 0.5 ; rmdir \"\(mountPoint)\" 2>/dev/null || true"
        let result = runCommand(cmd: combinedCmd)
        reply(result.0, result.1)
    }
    
    private func runCommand(cmd: String) -> (Bool, String?) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", cmd]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            return (task.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.conaksoft.zydisk.daemon")
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
