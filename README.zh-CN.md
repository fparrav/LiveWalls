# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 其他语言阅读

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

一个原生的 macOS 应用程序，可将视频用作动态壁纸。

## 🎥 什么是 LiveWalls？

**LiveWalls** 允许您将任何 MP4 或 MOV 视频转换为 macOS 的动态壁纸。视频完美适应您的屏幕，在多个显示器上工作，并始终保持在后台，不会干扰您的工作。

## ✨ 功能

- 🎬 **MP4 和 MOV 视频支持**
- 📱 **智能缩放**：视频自动调整到您的屏幕
- 🖥️ **多屏幕**：在所有连接的显示器上工作
- 🏢 **所有桌面**：在所有 macOS 工作空间显示
- 👻 **后台执行**：不干扰其他应用程序
- 🎛️ **图形界面**：带缩略图的可视化视频管理
- 🔄 **循环播放**：视频自动重复
- 📍 **状态栏菜单**：从菜单栏快速控制
- 🚀 **自动启动**：与系统一起启动的选项
- ⚙️ **持久性**：重启时记住您的最后一个壁纸

## 🎮 使用方法

### 1. 添加视频

- 点击"+"按钮选择视频
- 将 MP4 或 MOV 文件拖到应用程序中

### 2. 设置壁纸

- 从列表中选择一个视频
- 点击"设为壁纸"
- 享受您的动态背景！

### 3. 快速控制

- 使用菜单栏图标控制播放
- 启用/禁用自动启动
- 从后台打开应用

## 📋 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0 或更高版本（从源代码编译时）

## ⚙️ 安装

### 📥 下载发布版本（推荐）

从 [GitHub Releases](https://github.com/fparrav/LiveWalls/releases/latest) 下载最新的编译版本。

**⚠️ 重要提示：** 由于应用程序未使用 Apple 开发者证书签名，您需要手动允许其运行。

#### 方法 1：终端命令（推荐）

```bash
sudo xattr -rd com.apple.quarantine /path/to/LiveWalls.app
```

#### 方法 2：系统设置

1. 尝试打开 LiveWalls（将出现安全警告）
2. 转到 **系统设置** → **隐私与安全性**
3. 查找"LiveWalls 已被阻止"并点击 **"仍要打开"**

#### 方法 3：右键点击

1. **右键点击** LiveWalls.app
2. 从上下文菜单中选择 **"打开"**
3. 在安全对话框中点击 **"打开"**

### 🛠️ 从源代码编译

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   编译的应用程序将在 `build/Debug/` 文件夹中。

## 🔒 安全和隐私

### 所需权限

- **辅助功能**：在桌面上设置壁纸
- **文件和文件夹**：访问选定的视频

**LiveWalls 是一个 100% 开源项目**，您可以自己查看和编译。

### 为什么应用程序未签名？

- Apple 开发者会员资格每年费用 99 美元
- 这是一个免费的非商业项目
- 您可以通过查看源代码来验证安全性

### 如何验证安全性

1. **查看此存储库中的源代码**
2. **使用 Xcode 自己编译**
3. **在运行前检查构建**

## 🚀 开发

对于想要贡献或更好地理解代码的开发者，请参阅开发文档。

## 📄 许可证

此项目采用 MIT 许可证。有关详细信息，请参阅 `LICENSE` 文件。

## 🤝 贡献

欢迎贡献！请：

1. Fork 存储库
2. 创建功能分支
3. 进行更改
4. 提交拉取请求

## ⭐ 支持

如果您喜欢 LiveWalls，请在 GitHub 上给它一个星标！这有助于其他用户发现该项目。

---

**为 macOS 社区用 ❤️ 制作**
