import Foundation
import Security

// ZyDisk yardımcı servisi (root olarak launchd tarafından çalıştırılır).
//
// Güvenlik ilkeleri:
//  - Yalnızca ZyDisk uygulamasının imzasını taşıyan istemciler kabul edilir.
//  - Hiçbir komut kabuk (sh -c) üzerinden çalıştırılmaz; argümanlar dizi olarak verilir.
//  - Bağlama noktası yalnızca /Volumes/<güvenli-ad> olabilir ve yalnızca 127.0.0.1 kaynaklı
//    NFS bağlantıları ayrılabilir.

let helperBinaryPath = "/Library/PrivilegedHelperTools/\(ZyDiskDaemonLabel)"
let launchDaemonPlistPath = "/Library/LaunchDaemons/\(ZyDiskDaemonLabel).plist"

// MARK: - İmza yardımcıları

/// Bu ikilinin imzalandığı Team ID (ad-hoc imzalıysa nil).
let selfTeamID: String? = {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return dict[kSecCodeInfoTeamIdentifier as String] as? String
}()

/// İstemci (uygulama) için kod imzası gereksinimi.
/// Team ID varsa Apple sertifika zinciri + aynı ekip zorunludur; ad-hoc geliştirme
/// derlemelerinde yalnızca bundle kimliği kontrol edilebilir.
var clientRequirement: String {
    if let team = selfTeamID {
        return "identifier \"\(ZyDiskAppIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
    return "identifier \"\(ZyDiskAppIdentifier)\""
}

func staticCodeSatisfies(path: String, requirement: String) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
          let code = staticCode else { return false }
    var req: SecRequirement?
    guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req = req else { return false }
    return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
}

// MARK: - Komut çalıştırma

struct CommandResult {
    let status: Int32
    let output: String
    var ok: Bool { status == 0 }
}

/// Komutu kabuk kullanmadan çalıştırır; `timeout` saniye içinde bitmezse sonlandırır.
func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20) -> CommandResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var collected = Data()
    let lock = NSLock()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        lock.lock(); collected.append(chunk); lock.unlock()
    }

    let done = DispatchSemaphore(value: 0)
    task.terminationHandler = { _ in done.signal() }
    do {
        try task.run()
    } catch {
        pipe.fileHandleForReading.readabilityHandler = nil
        return CommandResult(status: -1, output: error.localizedDescription)
    }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        task.terminate()
        _ = done.wait(timeout: .now() + 2)
        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        pipe.fileHandleForReading.readabilityHandler = nil
        return CommandResult(status: -2, output: "Komut zaman aşımına uğradı: \(executable) \(arguments.joined(separator: " "))")
    }
    pipe.fileHandleForReading.readabilityHandler = nil
    let rest = pipe.fileHandleForReading.readDataToEndOfFile()
    lock.lock(); collected.append(rest); let data = collected; lock.unlock()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return CommandResult(status: task.terminationStatus, output: output)
}

// MARK: - Bağlama noktası doğrulama

let mountPointPattern = try! NSRegularExpression(pattern: "^/Volumes/[A-Za-z0-9_-]{1,64}$")

func isValidMountPoint(_ path: String) -> Bool {
    let range = NSRange(path.startIndex..., in: path)
    return mountPointPattern.firstMatch(in: path, range: range) != nil
}

struct MountInfo {
    let fsType: String
    let from: String
}

/// `path` tam olarak bir bağlama noktasıysa bilgilerini döndürür.
func mountInfo(at path: String) -> MountInfo? {
    var fs = statfs()
    guard statfs(path, &fs) == 0 else { return nil }
    let onName = withUnsafePointer(to: &fs.f_mntonname) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    guard onName == path else { return nil }
    let type = withUnsafePointer(to: &fs.f_fstypename) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
    }
    let from = withUnsafePointer(to: &fs.f_mntfromname) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    return MountInfo(fsType: type, from: from)
}

func isOurNFSMount(_ info: MountInfo) -> Bool {
    return info.fsType == "nfs" && (info.from.hasPrefix("127.0.0.1:") || info.from.hasPrefix("localhost:"))
}

/// Bağlı değilse ve boşsa bağlama klasörünü kaldırır.
func removeMountDirectoryIfEmpty(_ path: String) {
    guard mountInfo(at: path) == nil else { return }
    if let items = try? FileManager.default.contentsOfDirectory(atPath: path), items.isEmpty {
        rmdir(path)
    }
}

// MARK: - XPC servisi

@objc class Daemon: NSObject, DaemonProtocol {
    func version(withReply reply: @escaping (String) -> Void) {
        reply(ZyDiskDaemonVersion)
    }

    func mountNFS(port: Int, mountPoint: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidMountPoint(mountPoint) else {
            reply(false, "Geçersiz bağlama noktası: \(mountPoint)"); return
        }
        guard (1024...65535).contains(port) else {
            reply(false, "Geçersiz port: \(port)"); return
        }

        if let existing = mountInfo(at: mountPoint) {
            if isOurNFSMount(existing) {
                reply(false, "\(mountPoint) zaten bağlı."); return
            }
            reply(false, "\(mountPoint) başka bir birim tarafından kullanılıyor."); return
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: mountPoint, isDirectory: &isDir) {
            guard isDir.boolValue else {
                reply(false, "\(mountPoint) bir klasör değil."); return
            }
            let items = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint)) ?? []
            guard items.isEmpty else {
                reply(false, "\(mountPoint) klasörü boş değil; aynı adda başka bir birim olabilir."); return
            }
        } else {
            do {
                try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o755])
            } catch {
                reply(false, "Bağlama klasörü oluşturulamadı: \(error.localizedDescription)"); return
            }
        }

        // soft+intr: rclone yeniden başlatılırken kısa kesintiler hata yerine yeniden denemeyle atlatılır,
        // sunucu tamamen düşerse Finder sonsuza kadar kilitlenmez.
        let options = [
            "vers=3", "tcp", "port=\(port)", "mountport=\(port)",
            "resvport", "locallocks", "soft", "intr", "timeo=50", "retrans=6",
            "nonegnamecache",
        ].joined(separator: ",")
        let result = run("/sbin/mount_nfs", ["-o", options, "127.0.0.1:/", mountPoint], timeout: 30)
        if !result.ok {
            removeMountDirectoryIfEmpty(mountPoint)
            reply(false, result.output.isEmpty ? "mount_nfs başarısız (\(result.status))" : result.output)
            return
        }
        reply(true, nil)
    }

    func unmount(mountPoint: String, force: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidMountPoint(mountPoint) else {
            reply(false, "Geçersiz bağlama noktası: \(mountPoint)"); return
        }
        guard let info = mountInfo(at: mountPoint) else {
            // Zaten ayrılmış — artık klasörü temizleyip başarı dön.
            removeMountDirectoryIfEmpty(mountPoint)
            reply(true, nil); return
        }
        guard isOurNFSMount(info) else {
            reply(false, "\(mountPoint) ZyDisk tarafından bağlanmamış; ayrılmadı."); return
        }

        var last = run("/usr/sbin/diskutil", ["unmount", mountPoint], timeout: 15)
        if !last.ok && mountInfo(at: mountPoint) != nil && force {
            last = run("/sbin/umount", ["-f", mountPoint], timeout: 15)
            if !last.ok && mountInfo(at: mountPoint) != nil {
                last = run("/usr/sbin/diskutil", ["unmount", "force", mountPoint], timeout: 15)
            }
        }

        if mountInfo(at: mountPoint) == nil {
            removeMountDirectoryIfEmpty(mountPoint)
            reply(true, nil)
        } else {
            reply(false, last.output.isEmpty ? "Birim meşgul; açık dosyaları kapatıp tekrar deneyin." : last.output)
        }
    }

    func update(fromPath path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let team = selfTeamID else {
            reply(false, "AD_HOC"); return
        }
        guard path.hasSuffix(".app/Contents/MacOS/ZyDiskDaemon") else {
            reply(false, "Geçersiz güncelleme yolu"); return
        }
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard staticCodeSatisfies(path: path, requirement: requirement) else {
            reply(false, "Yeni servis ikilisinin imzası doğrulanamadı"); return
        }
        let tmp = helperBinaryPath + ".new"
        let fm = FileManager.default
        try? fm.removeItem(atPath: tmp)
        do {
            try fm.copyItem(atPath: path, toPath: tmp)
            chmod(tmp, 0o755)
            chown(tmp, 0, 0)
            guard rename(tmp, helperBinaryPath) == 0 else {
                reply(false, "Servis dosyası değiştirilemedi"); return
            }
        } catch {
            reply(false, error.localizedDescription); return
        }
        reply(true, nil)
        // launchd bir sonraki XPC isteğinde yeni ikiliyi başlatır.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    func uninstall(withReply reply: @escaping (Bool, String?) -> Void) {
        unlink(launchDaemonPlistPath)
        unlink(helperBinaryPath)
        reply(true, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = run("/bin/launchctl", ["bootout", "system/\(ZyDiskDaemonLabel)"], timeout: 5)
            exit(0)
        }
    }
}

class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // İmza gereksinimini sağlamayan istemcilerin mesajları sistem tarafından reddedilir.
        newConnection.setCodeSigningRequirement(clientRequirement)
        newConnection.exportedInterface = NSXPCInterface(with: DaemonProtocol.self)
        newConnection.exportedObject = Daemon()
        newConnection.resume()
        return true
    }
}

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: ZyDiskDaemonLabel)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
