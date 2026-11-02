<div align="center">
  <img src="docs/logo.png" alt="ZyDisk Logo" width="128" height="128">
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
- **Zero-Password Workflow:** A signed-caller-only privileged helper (`ZyDiskDaemon`) is installed once. After that, mounting and ejecting never ask for your Mac password. The helper updates itself when the app is updated (Team-signed builds).
- **Touch ID for sensitive actions:** Revealing a saved password or resetting the app is confirmed with Touch ID, falling back to your Mac password when Touch ID isn't available.
- **No `._` clutter on your server:** macOS writes AppleDouble (`._file`) and `.DS_Store` files over NFS. ZyDisk removes them from the server as soon as they are uploaded, and can sweep existing ones with one click.
- **Uninterrupted mounts:** rclone runs supervised with an on-disk NFS handle cache. If it crashes it is restarted on the same port and Finder keeps working. Drives survive an app restart and are adopted again, and pending uploads finish before rclone is stopped.
- **Secure by Default:** Passwords live in the macOS Keychain and are passed to rclone only through its process environment. Nothing is written to `rclone.conf` or exposed in process arguments.
- **Live status:** Upload queue and speed per drive, auto-mount on launch, launch at login, and connect/eject from the menu bar.
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
