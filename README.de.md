# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 In anderen Sprachen lesen

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

Eine native macOS-Anwendung zur Verwendung von Videos als dynamische Hintergrundbilder.

## 🎥 Was ist LiveWalls?

**LiveWalls** ermöglicht es dir, jedes MP4- oder MOV-Video in ein dynamisches Hintergrundbild für macOS umzuwandeln. Videos passen sich perfekt an deinen Bildschirm an, funktionieren auf mehreren Monitoren und bleiben immer im Hintergrund, ohne deine Arbeit zu stören.

## ✨ Funktionen

- 🎬 **MP4- und MOV-Video-Unterstützung**
- 📱 **Intelligente Skalierung**: Videos passen sich automatisch an deinen Bildschirm an
- 🖥️ **Mehrere Bildschirme**: Funktioniert auf allen angeschlossenen Displays
- 🏢 **Alle Desktops**: Zeigt auf allen macOS-Arbeitsbereich-Spaces an
- 👻 **Hintergrundausführung**: Stört andere Anwendungen nicht
- 🎛️ **Grafische Benutzeroberfläche**: Visuelle Videoverwaltung mit Miniaturansichten
- 🔄 **Schleifenwiedergabe**: Videos wiederholen sich automatisch
- 📍 **Statusleisten-Menü**: Schnelle Steuerung über die Menüleiste
- 🚀 **Auto-Start**: Option zum Starten mit dem System
- ⚙️ **Persistenz**: Merkt sich dein letztes Hintergrundbild beim Neustart

## 🎮 Verwendung

### 1. Videos hinzufügen

- Klicke auf die "+" Schaltfläche, um Videos auszuwählen
- Ziehe MP4- oder MOV-Dateien in die Anwendung

### 2. Hintergrundbild festlegen

- Wähle ein Video aus der Liste
- Klicke auf "Als Hintergrundbild festlegen"
- Genieße deinen dynamischen Hintergrund!

### 3. Schnelle Steuerung

- Verwende das Menüleisten-Symbol zur Wiedergabesteuerung
- Auto-Start aktivieren/deaktivieren
- App aus dem Hintergrund öffnen

## 📋 Anforderungen

- macOS 14.0 (Sonoma) oder neuer
- Xcode 15.0 oder neuer (um aus dem Quellcode zu kompilieren)

## ⚙️ Installation

### 📥 Release herunterladen (Empfohlen)

1. Gehe zu [GitHub Releases](https://github.com/fparrav/LiveWalls/releases)
2. Lade die neueste `.dmg`-Datei herunter
3. Öffne das DMG und ziehe LiveWalls in den Programme-Ordner

### 🍺 Homebrew Installation (Empfohlen für fortgeschrittene Benutzer)

**Kein Homebrew installiert?** [Hier installieren](https://brew.sh)

```bash
brew tap fparrav/livewalls
brew install livewalls
```

**Vorteile der Homebrew-Methode:**
- ✅ Automatische Installation ohne manuelle Konfiguration
- ✅ Keine macOS-Quarantäne-Probleme  
- ✅ Einfache Updates mit `brew upgrade`

**📋 Hinweis:** LiveWalls ist nicht im offiziellen Homebrew-Repository, da es ein Apple Developer-Zertifikat (99$/Jahr) für signierte Apps benötigt. Als kostenloses Open-Source-Projekt verwenden wir einen persönlichen "Tap", der eine sichere Verteilung unsignierter Apps ermöglicht.

### ⚠️ Wichtig: Nicht signierte Anwendung

**LiveWalls ist ein Open-Source-Projekt** und besitzt kein Apple Developer-Zertifikat (99$/Jahr).
Um die Anwendung zum ersten Mal zu öffnen:

#### Methode 1: Terminal-Befehl (Empfohlen)

```bash
sudo xattr -rd com.apple.quarantine /pfad/zu/LiveWalls.app
```

#### Methode 2: Systemeinstellungen

1. Versuche LiveWalls zu öffnen (eine Sicherheitswarnung erscheint)
2. Gehe zu **Systemeinstellungen** → **Datenschutz & Sicherheit**
3. Suche nach "LiveWalls wurde blockiert" und klicke **"Trotzdem öffnen"**

#### Methode 3: Rechtsklick

1. **Rechtsklick** auf LiveWalls.app
2. Wähle **"Öffnen"** aus dem Kontextmenü
3. Klicke **"Öffnen"** im Sicherheitsdialog

### 🛠️ Aus Quellcode kompilieren

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   Die kompilierte App befindet sich im `build/Debug/` Ordner.

## 🔒 Sicherheit und Datenschutz

### Erforderliche Berechtigungen

- **Bedienungshilfen**: Um das Hintergrundbild auf dem Desktop zu setzen
- **Dateien und Ordner**: Um auf ausgewählte Videos zuzugreifen

**LiveWalls ist ein 100% Open Source-Projekt**, das du selbst überprüfen und kompilieren kannst.

### Warum ist die App nicht signiert?

- Apple Developer-Mitgliedschaft kostet $99 USD/Jahr
- Dies ist ein kostenloses Projekt ohne kommerzielle Zwecke
- Du kannst die Sicherheit durch Überprüfung des Quellcodes verifizieren

### Wie man die Sicherheit überprüft

1. **Überprüfe den Quellcode** in diesem Repository
2. **Kompiliere selbst** mit Xcode
3. **Inspiziere den Build** vor der Ausführung

## 🚀 Entwicklung

Für Entwickler, die beitragen oder den Code besser verstehen möchten, siehe die Entwicklungsdokumentation.

## 📄 Lizenz

Dieses Projekt steht unter der MIT-Lizenz. Siehe die `LICENSE` Datei für Details.

## 🤝 Beitragen

Beiträge sind willkommen! Bitte:

1. Forke das Repository
2. Erstelle einen Feature-Branch
3. Mache deine Änderungen
4. Reiche einen Pull Request ein

## ⭐ Unterstützung

Wenn dir LiveWalls gefällt, gib ihm bitte einen Stern auf GitHub! Das hilft anderen Benutzern, das Projekt zu entdecken.

---

**Mit ❤️ für die macOS-Community gemacht**
