# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 Read in other languages

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

A native macOS application to use videos as dynamic wallpapers.

## 🎥 What is LiveWalls?

**LiveWalls** allows you to turn any MP4 or MOV video into a dynamic wallpaper for macOS. Videos adapt perfectly to your screen, work on multiple monitors, and always stay in the background without interfering with your work.

## ✨ Features

- 🎬 **MP4 and MOV video support**
- 📱 **Smart scaling**: Videos automatically adjust to your screen
- 🖥️ **Multiple screens**: Works on all connected displays
- 🏢 **All desktops**: Shows on all macOS workspace spaces
- 👻 **Background execution**: Doesn't interfere with other applications
- 🎛️ **Graphical interface**: Visual video management with thumbnails
- 🔄 **Loop playback**: Videos repeat automatically
- 📍 **Status bar menu**: Quick control from the menu bar
- 🚀 **Auto-start**: Option to start with the system
- ⚙️ **Persistence**: Remembers your last wallpaper on restart

## 🎮 Usage

### 1. Add Videos

- Click the "+" button to select videos
- Drag MP4 or MOV files to the application

### 2. Set Wallpaper

- Select a video from the list
- Click "Set as Wallpaper"
- Enjoy your dynamic background!

### 3. Quick Control

- Use the menu bar icon to control playback
- Enable/disable auto-start
- Open the app from the background

## 📋 Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (to compile from source)

## ⚙️ Installation

### 📥 Download Release (Recommended)

Download the latest compiled version from [GitHub Releases](https://github.com/fparrav/LiveWalls/releases/latest).

**⚠️ Important:** Since the app is not signed with an Apple Developer certificate, you'll need to manually allow it to run.

#### Method 1: Terminal Command (Recommended)

```bash
sudo xattr -rd com.apple.quarantine /path/to/LiveWalls.app
```

#### Method 2: System Settings

1. Try to open LiveWalls (a security warning will appear)
2. Go to **System Settings** → **Privacy & Security**
3. Look for "LiveWalls was blocked" and click **"Open Anyway"**

#### Method 3: Right-click

1. **Right-click** on LiveWalls.app
2. Select **"Open"** from the context menu
3. Click **"Open"** in the security dialog

### 🛠️ Compile from Source

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   The compiled app will be in the `build/Debug/` folder.

## 🔒 Security and Privacy

### Required permissions

- **Accessibility**: To set the wallpaper on the desktop
- **Files and Folders**: To access selected videos

**LiveWalls is a 100% open source project** that you can review and compile yourself.

### Why isn't the app signed?

- Apple Developer membership costs $99 USD/year
- This is a free project with no commercial purpose
- You can verify the security by reviewing the source code

### How to verify security

1. **Review the source code** in this repository
2. **Compile yourself** using Xcode
3. **Inspect the build** before running it

## 🚀 Development

For developers who want to contribute or understand the code better, see the development documentation.

## 📄 License

This project is under the MIT License. See the `LICENSE` file for details.

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## ⭐ Support

If you like LiveWalls, please give it a star on GitHub! This helps other users discover the project.

---

**Made with ❤️ for the macOS community**
