# ZyDisk — Ürün Sayfası Metinleri (conaksoft.com)

Bu dosya conaksoft.com "Ürünler" bölümü için hazır metinler içerir. Logo: `docs/logo.png`.

---

## Türkçe

**Ürün adı:** ZyDisk

**Slogan:** Sunucularınız, Finder'da bir disk gibi.

**Kısa açıklama (kart / liste görünümü, ~150 karakter):**
SFTP, FTP/FTPS ve S3 depolamalarınızı macOS Finder'da yerel bir disk gibi bağlayan, parola sormayan ve kurulum gerektirmeyen yerel Mac uygulaması.

**Uzun açıklama:**
ZyDisk, uzak sunucularınızı ve bulut depolamalarınızı Mac'inizde sıradan bir sürücüye dönüştürür. Bir SFTP sunucusundaki ya da S3 bucket'ındaki dosyaları Finder'da açın, VS Code'da düzenleyin, kaydedin; hepsi kendi diskinizdeymiş gibi çalışır.

ZyDisk, kendini kanıtlamış rclone motorunu ve macOS'un yerleşik NFS istemcisini kullanır. macFUSE, çekirdek uzantısı veya Apple Silicon'da güvenlik ayarlarını düşürmek gerekmez. Bir kez onayladığınız arka plan servisi sayesinde sürücü bağlarken ve ayırırken bir daha parola sorulmaz. Parolalarınız macOS Anahtar Zinciri'nde saklanır, hassas işlemler Touch ID ile onaylanır.

**Öne çıkan özellikler:**
- SFTP/SSH, FTP, FTPS ve S3 uyumlu depolama (AWS S3, Cloudflare R2, MinIO, Wasabi, Backblaze B2…)
- Finder'da yerel disk olarak görünür; macFUSE veya çekirdek uzantısı gerektirmez
- Tek seferlik kurulumdan sonra parolasız bağlama ve ayırma
- Touch ID ile hassas işlem onayı
- Sunucuda `._` ve `.DS_Store` çöpü bırakmaz
- Kesintisiz çalışma: motor çökerse saniyeler içinde kendini toparlar, bekleyen yüklemeler tamamlanır
- Canlı yükleme durumu ve hız göstergesi
- Arama, filtreleme, sıralama ve gruplama ile çok sayıda sürücüyü kolayca yönetme
- Menü çubuğundan tek tıkla bağla/ayır, açılışta otomatik bağlanma
- Tek tıkla Finder, VS Code veya Terminal'de açma
- Veri toplamaz; tüm bilgiler yalnızca sizin Mac'inizde kalır

**Kimler için?**
Sitelerini doğrudan sunucuda düzenleyen web geliştiricileri, FTP üzerinden dosya paylaşan ekipler ve S3 uyumlu depolama kullanan herkes.

**Sistem gereksinimleri:** macOS 13 Ventura veya üzeri · Apple Silicon ve Intel · Tek seferlik kurulum için yönetici hesabı

**Bağlantılar:** GitHub: https://github.com/conaksoft/zydisk · İndir: https://github.com/conaksoft/zydisk/releases

**SEO anahtar kelimeleri:** mac sftp sürücü, mac ftp bağlama, s3 finder, macos sunucu disk olarak bağlama, macfuse alternatifi, rclone mac arayüzü

---

## English

**Product name:** ZyDisk

**Tagline:** Your servers, as a drive in Finder.

**Short description (~150 characters):**
A native Mac app that mounts SFTP, FTP/FTPS and S3 storage as local drives in Finder — no macFUSE, no kernel extensions, no password prompts.

**Long description:**
ZyDisk turns your remote servers and cloud storage into ordinary drives on your Mac. Open files on an SFTP server or an S3 bucket in Finder, edit them in VS Code and save, just as if they were on your own disk.

ZyDisk uses the proven rclone engine together with macOS's built-in NFS client, so there's no macFUSE, no kernel extension and no need to lower security settings on Apple Silicon. You approve a background helper once, and connecting and ejecting drives never ask for your password again. Passwords are stored in the macOS Keychain and sensitive actions are confirmed with Touch ID.

**Highlights:**
- SFTP/SSH, FTP, FTPS and S3-compatible storage (AWS S3, Cloudflare R2, MinIO, Wasabi, Backblaze B2…)
- Appears as a native drive in Finder, with no macFUSE or kernel extension
- Password-free mounting and ejecting after a one-time setup
- Touch ID confirmation for sensitive actions
- Leaves no `._` or `.DS_Store` clutter on your server
- Recovers within seconds if the engine stops, and finishes pending uploads
- Live upload status and transfer speed
- Search, filter, sort and group many drives
- Connect and eject from the menu bar, with auto-connect on launch
- Open any drive in Finder, VS Code or Terminal with one click
- No data collection: everything stays on your Mac

**Requirements:** macOS 13 Ventura or later · Apple Silicon & Intel · Administrator account for the one-time setup

---

## Ürün sayfası için kısa sorumluluk reddi notu

> ZyDisk "olduğu gibi" sunulur. Conaksoft, uygulamanın kullanımından doğabilecek veri kaybı veya diğer zararlardan sorumlu tutulamaz. Önemli verilerinizin her zaman yedeğini alın. Ayrıntılı koşullar: https://github.com/conaksoft/zydisk#disclaimer
