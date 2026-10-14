import Cocoa
import FlutterMacOS
import LocalAuthentication
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
    private var daemonConnection: NSXPCConnection?
    private var channel: FlutterMethodChannel?
    /// Dart tarafı temizliği bitirip `quitNow` çağırana kadar çıkış ertelenir.
    private var allowTerminate = false

    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "com.conaksoft.zydisk/daemon", binaryMessenger: controller.engine.binaryMessenger)
        self.channel = channel

        channel.setMethodCallHandler { [weak self] (call, rawResult) in
            guard let self = self else { return }
            let result = OnceResult(rawResult)
            let args = call.arguments as? [String: Any] ?? [:]

            switch call.method {
            case "daemonVersion":
                self.daemonVersion(result: result)
            case "mount":
                guard let port = args["port"] as? Int, let mountPoint = args["mountPoint"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "port/mountPoint eksik", details: nil)); return
                }
                self.callDaemon(result: result, timeout: 40) { proxy, reply in
                    proxy.mountNFS(port: port, mountPoint: mountPoint, withReply: reply)
                }
            case "unmount":
                guard let mountPoint = args["mountPoint"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "mountPoint eksik", details: nil)); return
                }
                let force = args["force"] as? Bool ?? true
                self.callDaemon(result: result, timeout: 60) { proxy, reply in
                    proxy.unmount(mountPoint: mountPoint, force: force, withReply: reply)
                }
            case "updateDaemon":
                let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ZyDiskDaemon").path
                self.callDaemon(result: result, timeout: 15) { proxy, reply in
                    proxy.update(fromPath: path, withReply: reply)
                }
            case "uninstallDaemon":
                self.callDaemon(result: result, timeout: 10) { proxy, reply in
                    proxy.uninstall(withReply: reply)
                }
            case "bundledDaemonVersion":
                result(ZyDiskDaemonVersion)
            case "authenticate":
                let reason = args["reason"] as? String ?? "ZyDisk kimliğinizi doğrulamak istiyor."
                self.authenticate(reason: reason, result: result)
            case "biometryAvailable":
                let ctx = LAContext()
                result(ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
            case "getLaunchAtLogin":
                if #available(macOS 13.0, *) {
                    result(SMAppService.mainApp.status == .enabled)
                } else {
                    result(false)
                }
            case "setLaunchAtLogin":
                let enabled = args["enabled"] as? Bool ?? false
                self.setLaunchAtLogin(enabled, result: result)
            case "quitNow":
                result(nil)
                self.allowTerminate = true
                DispatchQueue.main.async { NSApp.terminate(nil) }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Daemon (XPC)

    private func connection() -> NSXPCConnection {
        if let existing = daemonConnection { return existing }
        let conn = NSXPCConnection(machServiceName: ZyDiskDaemonLabel, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: DaemonProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.daemonConnection = nil }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.daemonConnection = nil }
        }
        conn.resume()
        daemonConnection = conn
        return conn
    }

    /// Daemon'a bir çağrı yapar; hata, zaman aşımı ve yanıtın yalnızca bir kez iletilmesini garanti eder.
    private func callDaemon(result: OnceResult, timeout: TimeInterval,
                            _ body: @escaping (DaemonProtocol, @escaping (Bool, String?) -> Void) -> Void) {
        let conn = connection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.daemonConnection?.invalidate()
                self?.daemonConnection = nil
                result(FlutterError(code: "XPC_ERROR", message: error.localizedDescription, details: nil))
            }
        } as? DaemonProtocol

        guard let proxy = proxy else {
            result(FlutterError(code: "XPC_ERROR", message: "Servis vekili oluşturulamadı", details: nil)); return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            result(FlutterError(code: "TIMEOUT", message: "Servis yanıt vermedi", details: nil))
        }

        body(proxy) { success, message in
            DispatchQueue.main.async {
                if success {
                    result(true)
                } else {
                    result(FlutterError(code: "DAEMON_FAILED", message: message ?? "Bilinmeyen hata", details: nil))
                }
            }
        }
    }

    private func daemonVersion(result: OnceResult) {
        let conn = connection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.daemonConnection?.invalidate()
                self?.daemonConnection = nil
                result(FlutterError(code: "XPC_ERROR", message: error.localizedDescription, details: nil))
            }
        } as? DaemonProtocol
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            result(FlutterError(code: "TIMEOUT", message: "Servis yanıt vermedi", details: nil))
        }
        proxy?.version { version in
            DispatchQueue.main.async { result(version) }
        }
    }

    // MARK: - Touch ID / parola

    /// Touch ID varsa parmak izi, yoksa (veya iptal edilirse) Mac oturum parolası ister.
    private func authenticate(reason: String, result: OnceResult) {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Parola Kullan"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Bu Mac'te ne Touch ID ne de parola tabanlı doğrulama kullanılabiliyor; engelleme.
            result(true); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { result(success) }
        }
    }

    // MARK: - Oturum açılışında başlat

    private func setLaunchAtLogin(_ enabled: Bool, result: OnceResult) {
        guard #available(macOS 13.0, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "macOS 13 veya üzeri gerekli", details: nil)); return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            result(SMAppService.mainApp.status == .enabled)
        } catch {
            result(FlutterError(code: "LOGIN_ITEM", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Uygulama yaşam döngüsü

    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTerminate { return .terminateNow }
        // Dart tarafına haber ver: bekleyen yüklemeleri tamamlayıp sürücüleri güvenle ayırsın.
        if let channel = channel {
            channel.invokeMethod("quitRequested", arguments: nil)
            return .terminateCancel
        }
        return .terminateNow
    }

    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainFlutterWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menü çubuğunda çalışmaya devam eder.
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

/// FlutterResult'ın yalnızca bir kez çağrılmasını sağlar (XPC hata + yanıt + zaman aşımı yarışları için).
final class OnceResult {
    private var callback: FlutterResult?
    init(_ callback: @escaping FlutterResult) { self.callback = callback }
    func callAsFunction(_ value: Any?) {
        assert(Thread.isMainThread)
        guard let cb = callback else { return }
        callback = nil
        cb(value)
    }
}
