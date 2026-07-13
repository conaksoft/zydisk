<div align="center">
  <img src="assets/icons/tray_icon.png" alt="ZyDisk Logo" width="120" height="120">
  <h1>ZyDisk</h1>
  <p><b>Enterprise-Grade Cloud Storage Mounter for macOS</b></p>
  <p><i>Developed with ❤️ by <a href="https://conaksoft.com">Conaksoft</a></i></p>
</div>

---

## 🚀 Overview

**ZyDisk** is a powerful, native macOS desktop application designed to seamlessly mount your remote cloud storage and servers directly as local drives. Built on top of the robust `rclone` engine, ZyDisk utilizes macOS's **Native NFS loopback** mounting—eliminating the need for third-party kernel extensions like macFUSE. 

Whether you are a developer managing remote servers, a creative professional accessing S3 buckets, or an enterprise user connecting to FTPs, ZyDisk by Conaksoft brings your data natively into Finder with zero friction.

## ✨ Key Features

- **Native macOS Integration:** Mounts drives using native NFS. Say goodbye to FUSE installations, kernel panics, and security policy downgrades on Apple Silicon.
- **Multi-Protocol Support:** Connect to **SFTP/SSH**, **FTP**, **FTPS**, and **S3 Compatible** storage providers effortlessly.
- **Zero-Password Workflow:** Features a built-in macOS Privileged Helper Tool (`SMAppService`). Once authorized, you can mount and unmount drives instantly without ever typing your Mac password again.
- **Minimalist & Professional UI:** A distraction-free, dark-themed monochrome interface designed for power users.
- **Secure by Default:** Credentials and private keys are managed securely, ensuring your server access remains protected.
- **Developer Ready:** One-click shortcuts to open your mounted drives directly in **VS Code**, **Terminal**, or **Finder**.

## 🛠 Tech Stack

- **Frontend:** Flutter (macOS Desktop)
- **Backend Services:** Swift & Objective-C (XPC, SMAppService)
- **Mount Engine:** rclone (NFS Server)

## 📥 Installation

*(Coming Soon)*
Pre-compiled `.dmg` files will be available in the [Releases](https://github.com/shibware/zydisk/releases) section. 

## 🏗 Building from Source

If you prefer to compile ZyDisk yourself, ensure you have **Flutter**, **Xcode**, and **rclone** installed.

```bash
# Clone the repository
git clone https://github.com/shibware/zydisk.git
cd zydisk

# Get dependencies
flutter pub get

# Build for macOS
flutter build macos
```

## 🔒 Security & Privacy

ZyDisk respects your privacy. All your server credentials, paths, and configurations are stored **locally** on your machine. Conaksoft does not collect telemetry, usage data, or remote server credentials.

## 🏢 About Conaksoft

At **[Conaksoft](https://conaksoft.com)**, we build innovative digital solutions that bridge the gap between complex infrastructure and seamless user experiences. ZyDisk is a testament to our commitment to creating high-performance, native tools for professionals.

---
<div align="center">
  <p>Copyright © 2026 Conaksoft. All rights reserved.</p>
</div>
