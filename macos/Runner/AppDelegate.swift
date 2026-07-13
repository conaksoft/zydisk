import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
    var daemonConnection: NSXPCConnection?
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "com.conaksoft.zydisk/daemon", binaryMessenger: controller.engine.binaryMessenger)
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "installDaemon":
                self?.installDaemon(result: result)
            case "mount":
                if let args = call.arguments as? [String: Any],
                   let port = args["port"] as? Int,
                   let mountPoint = args["mountPoint"] as? String {
                    self?.mountDaemon(port: port, mountPoint: mountPoint, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing port or mountPoint", details: nil))
                }
            case "unmount":
                if let args = call.arguments as? [String: Any],
                   let mountPoint = args["mountPoint"] as? String {
                    self?.unmountDaemon(mountPoint: mountPoint, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing mountPoint", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func installDaemon(result: @escaping FlutterResult) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.conaksoft.zydisk.daemon.plist")
            do {
                if service.status == SMAppService.Status.enabled {
                    result(true)
                    return
                }
                try service.register()
                result(true)
            } catch {
                result(FlutterError(code: "DAEMON_ERROR", message: "Failed to install daemon: \(error.localizedDescription)", details: nil))
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED_OS", message: "SMAppService requires macOS 13.0 or newer", details: nil))
        }
    }
    
    private func setupDaemonConnection() -> Bool {
        if daemonConnection == nil {
            daemonConnection = NSXPCConnection(machServiceName: "com.conaksoft.zydisk.daemon", options: .privileged)
            daemonConnection?.remoteObjectInterface = NSXPCInterface(with: DaemonProtocol.self)
            daemonConnection?.invalidationHandler = { [weak self] in
                self?.daemonConnection = nil
            }
            daemonConnection?.interruptionHandler = { [weak self] in
                self?.daemonConnection = nil
            }
            daemonConnection?.resume()
        }
        return daemonConnection != nil
    }
    
    private func mountDaemon(port: Int, mountPoint: String, result: @escaping FlutterResult) {
        if !setupDaemonConnection() {
            result(FlutterError(code: "DAEMON_NOT_AVAILABLE", message: "Daemon connection failed", details: nil))
            return
        }
        
        let proxy = daemonConnection?.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                result(FlutterError(code: "XPC_ERROR", message: "Servise bağlanılamadı: \(error.localizedDescription). Lütfen ayarlardan veya menüden Servisi Kur işlemini gerçekleştirin.", details: nil))
            }
        }) as? DaemonProtocol
        
        proxy?.mountNFS(port: port, mountPoint: mountPoint) { success, error in
            DispatchQueue.main.async {
                if success {
                    result(true)
                } else {
                    result(FlutterError(code: "MOUNT_FAILED", message: error ?? "Unknown error", details: nil))
                }
            }
        }
    }
    
    private func unmountDaemon(mountPoint: String, result: @escaping FlutterResult) {
        if !setupDaemonConnection() {
            result(FlutterError(code: "DAEMON_NOT_AVAILABLE", message: "Daemon connection failed", details: nil))
            return
        }
        
        let proxy = daemonConnection?.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                result(FlutterError(code: "XPC_ERROR", message: "Servise bağlanılamadı: \(error.localizedDescription). Lütfen ayarlardan veya menüden Servisi Kur işlemini gerçekleştirin.", details: nil))
            }
        }) as? DaemonProtocol
        
        proxy?.unmount(mountPoint: mountPoint) { success, error in
            DispatchQueue.main.async {
                if success {
                    result(true)
                } else {
                    result(FlutterError(code: "UNMOUNT_FAILED", message: error ?? "Unknown error", details: nil))
                }
            }
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
