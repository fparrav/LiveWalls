# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 Leggi in altre lingue

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

Un'applicazione nativa per macOS per utilizzare video come sfondi dinamici.

## 🎥 Cos'è LiveWalls?

**LiveWalls** ti permette di trasformare qualsiasi video MP4 o MOV in uno sfondo dinamico per macOS. I video si adattano perfettamente al tuo schermo, funzionano su più monitor e rimangono sempre in background senza interferire con il tuo lavoro.

## ✨ Caratteristiche

- 🎬 **Supporto video MP4 e MOV**
- 📱 **Ridimensionamento intelligente**: I video si adattano automaticamente al tuo schermo
- 🖥️ **Schermi multipli**: Funziona su tutti i display collegati
- 🏢 **Tutti i desktop**: Visualizza su tutti gli spazi di lavoro di macOS
- 👻 **Esecuzione in background**: Non interferisce con altre applicazioni
- 🎛️ **Interfaccia grafica**: Gestione visiva dei video con miniature
- 🔄 **Riproduzione in loop**: I video si ripetono automaticamente
- 📍 **Menu barra di stato**: Controllo rapido dalla barra dei menu
- 🚀 **Avvio automatico**: Opzione per avviare con il sistema
- ⚙️ **Persistenza**: Ricorda il tuo ultimo sfondo al riavvio

## 🎮 Utilizzo

### 1. Aggiungi Video

- Clicca il pulsante "+" per selezionare video
- Trascina file MP4 o MOV nell'applicazione

### 2. Imposta Sfondo

- Seleziona un video dalla lista
- Clicca "Imposta come Sfondo"
- Goditi il tuo background dinamico!

### 3. Controllo Rapido

- Usa l'icona della barra dei menu per controllare la riproduzione
- Abilita/disabilita l'avvio automatico
- Apri l'app dal background

## 📋 Requisiti

- macOS 14.0 (Sonoma) o successivo
- Xcode 15.0 o successivo (per compilare dal codice sorgente)

## ⚙️ Installazione

### 📥 Scarica Release (Raccomandato)

1. Vai su [GitHub Releases](https://github.com/fparrav/LiveWalls/releases)
2. Scarica il file `.dmg` più recente
3. Apri il DMG e trascina LiveWalls nella cartella Applicazioni

### 🍺 Installazione Homebrew (Raccomandato per utenti avanzati)

**Non hai Homebrew?** [Installalo qui](https://brew.sh)

```bash
brew tap fparrav/livewalls
brew install livewalls
```

**Vantaggi del metodo Homebrew:**
- ✅ Installazione automatica senza configurazione manuale
- ✅ Nessun problema di quarantena macOS  
- ✅ Aggiornamenti facili con `brew upgrade`

**📋 Nota:** LiveWalls non è nel repository ufficiale di Homebrew perché richiede un certificato Apple Developer (99$/anno) per app firmate. Come progetto open source gratuito, usiamo un "tap" personale che permette la distribuzione sicura di app non firmate.

### ⚠️ Importante: Applicazione Non Firmata

**LiveWalls è un progetto open source** e non possiede un certificato Apple Developer (99$/anno).
Per aprire l'applicazione per la prima volta:

#### Metodo 1: Comando Terminale (Raccomandato)

```bash
sudo xattr -rd com.apple.quarantine /percorso/a/LiveWalls.app
```

#### Metodo 2: Impostazioni di Sistema

1. Prova ad aprire LiveWalls (apparirà un avviso di sicurezza)
2. Vai in **Impostazioni di Sistema** → **Privacy e Sicurezza**
3. Cerca "LiveWalls è stato bloccato" e clicca **"Apri comunque"**

#### Metodo 3: Clic destro

1. **Clic destro** su LiveWalls.app
2. Seleziona **"Apri"** dal menu contestuale
3. Clicca **"Apri"** nel dialogo di sicurezza

### 🛠️ Compila dal Codice Sorgente

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   L'app compilata sarà nella cartella `build/Debug/`.

## 🔒 Sicurezza e Privacy

### Permessi richiesti

- **Accessibilità**: Per impostare lo sfondo sul desktop
- **File e Cartelle**: Per accedere ai video selezionati

**LiveWalls è un progetto 100% open source** che puoi rivedere e compilare tu stesso.

### Perché l'app non è firmata?

- L'appartenenza Apple Developer costa $99 USD/anno
- Questo è un progetto gratuito senza scopo commerciale
- Puoi verificare la sicurezza rivedendo il codice sorgente

### Come verificare la sicurezza

1. **Rivedi il codice sorgente** in questo repository
2. **Compila tu stesso** usando Xcode
3. **Ispeziona la build** prima di eseguirla

## 🚀 Sviluppo

Per gli sviluppatori che vogliono contribuire o capire meglio il codice, vedi la documentazione di sviluppo.

## 📄 Licenza

Questo progetto è sotto la Licenza MIT. Vedi il file `LICENSE` per i dettagli.

## 🤝 Contribuire

I contributi sono benvenuti! Per favore:

1. Fai il fork del repository
2. Crea un branch per la feature
3. Fai le tue modifiche
4. Invia una pull request

## ⭐ Supporto

Se ti piace LiveWalls, per favore metti una stella su GitHub! Questo aiuta altri utenti a scoprire il progetto.

---

**Fatto con ❤️ per la comunità macOS**
