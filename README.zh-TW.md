# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 其他語言閱讀

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

一個原生的 macOS 應用程式，可將影片用作動態桌布。

## 🎥 什麼是 LiveWalls？

**LiveWalls** 允許您將任何 MP4 或 MOV 影片轉換為 macOS 的動態桌布。影片完美適應您的螢幕，在多個顯示器上工作，並始終保持在背景，不會干擾您的工作。

## ✨ 功能

- 🎬 **MP4 和 MOV 影片支援**
- 📱 **智慧縮放**：影片自動調整到您的螢幕
- 🖥️ **多螢幕**：在所有連接的顯示器上工作
- 🏢 **所有桌面**：在所有 macOS 工作空間顯示
- 👻 **背景執行**：不干擾其他應用程式
- 🎛️ **圖形介面**：帶縮圖的視覺化影片管理
- 🔄 **循環播放**：影片自動重複
- 📍 **狀態列選單**：從選單列快速控制
- 🚀 **自動啟動**：與系統一起啟動的選項
- ⚙️ **持久性**：重新啟動時記住您的最後一個桌布

## 🎮 使用方法

### 1. 添加影片

- 點擊"+"按鈕選擇影片
- 將 MP4 或 MOV 檔案拖到應用程式中

### 2. 設定桌布

- 從清單中選擇一個影片
- 點擊"設為桌布"
- 享受您的動態背景！

### 3. 快速控制

- 使用選單列圖示控制播放
- 啟用/停用自動啟動
- 從背景開啟應用

## 📋 系統需求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0 或更高版本（從原始碼編譯時）

## ⚙️ 安裝

### 📥 下載發布版本（推薦）

從 [GitHub Releases](https://github.com/fparrav/LiveWalls/releases/latest) 下載最新的編譯版本。

**⚠️ 重要提示：** 由於應用程式未使用 Apple 開發者憑證簽名，您需要手動允許其執行。

#### 方法 1：終端機命令（推薦）

```bash
sudo xattr -rd com.apple.quarantine /path/to/LiveWalls.app
```

#### 方法 2：系統設定

1. 嘗試開啟 LiveWalls（將出現安全警告）
2. 前往 **系統設定** → **隱私權與安全性**
3. 尋找"LiveWalls 已被阻擋"並點擊 **"仍要打開"**

#### 方法 3：右鍵點擊

1. **右鍵點擊** LiveWalls.app
2. 從選單中選擇 **"開啟"**
3. 在安全對話框中點擊 **"開啟"**

### 🛠️ 從原始碼編譯

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   編譯的應用程式將在 `build/Debug/` 資料夾中。

## 🔒 安全和隱私

### 所需權限

- **輔助使用**：在桌面上設定桌布
- **檔案和資料夾**：存取選定的影片

**LiveWalls 是一個 100% 開源專案**，您可以自己查看和編譯。

### 為什麼應用程式未簽名？

- Apple 開發者會員資格每年費用 $99 USD
- 這是一個免費的非商業專案
- 您可以透過查看原始碼來驗證安全性

### 如何驗證安全性

1. **查看此存儲庫中的原始碼**
2. **使用 Xcode 自己編譯**
3. **在執行前檢查建置**

## 🚀 開發

對於想要貢獻或更好地理解程式碼的開發者，請參閱開發文件。

## 📄 授權

此專案採用 MIT 授權。有關詳細資訊，請參閱 `LICENSE` 檔案。

## 🤝 貢獻

歡迎貢獻！請：

1. Fork 存儲庫
2. 建立功能分支
3. 進行更改
4. 提交拉取請求

## ⭐ 支援

如果您喜歡 LiveWalls，請在 GitHub 上給它一個星標！這有助於其他使用者發現該專案。

---

**為 macOS 社群用 ❤️ 製作**
