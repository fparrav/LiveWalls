# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 Lire dans d'autres langues

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

Une application macOS native pour utiliser des vidéos comme fonds d'écran dynamiques.

## 🎥 Qu'est-ce que LiveWalls ?

**LiveWalls** vous permet de transformer n'importe quelle vidéo MP4 ou MOV en fond d'écran dynamique pour macOS. Les vidéos s'adaptent parfaitement à votre écran, fonctionnent sur plusieurs moniteurs et restent toujours en arrière-plan sans interférer avec votre travail.

## ✨ Fonctionnalités

- 🎬 **Support vidéo MP4 et MOV**
- 📱 **Mise à l'échelle intelligente** : Les vidéos s'ajustent automatiquement à votre écran
- 🖥️ **Écrans multiples** : Fonctionne sur tous les écrans connectés
- 🏢 **Tous les bureaux** : S'affiche sur tous les espaces de travail macOS
- 👻 **Exécution en arrière-plan** : N'interfère pas avec les autres applications
- 🎛️ **Interface graphique** : Gestion visuelle des vidéos avec miniatures
- 🔄 **Lecture en boucle** : Les vidéos se répètent automatiquement
- 📍 **Menu dans la barre d'état** : Contrôle rapide depuis la barre de menu
- 🚀 **Démarrage automatique** : Option pour démarrer avec le système
- ⚙️ **Persistance** : Se souvient de votre dernier fond d'écran au redémarrage

## 🎮 Utilisation

### 1. Ajouter des Vidéos

- Cliquez sur le bouton "+" pour sélectionner des vidéos
- Glissez-déposez des fichiers MP4 ou MOV dans l'application

### 2. Définir comme Fond d'écran

- Sélectionnez une vidéo dans la liste
- Cliquez sur "Définir comme Fond d'écran"
- Profitez de votre arrière-plan dynamique !

### 3. Contrôle Rapide

- Utilisez l'icône dans la barre de menu pour contrôler la lecture
- Activez/désactivez le démarrage automatique
- Ouvrez l'application depuis l'arrière-plan

## 📋 Exigences

- macOS 14.0 (Sonoma) ou plus récent
- Xcode 15.0 ou plus récent (pour compiler depuis la source)

## ⚙️ Installation

### 📥 Télécharger la Release (Recommandé)

1. Allez sur [GitHub Releases](https://github.com/fparrav/LiveWalls/releases)
2. Téléchargez le fichier `.dmg` le plus récent
3. Ouvrez le DMG et glissez LiveWalls vers Applications

### 🍺 Installation Homebrew (Recommandé pour utilisateurs avancés)

**Vous n'avez pas Homebrew ?** [Installez-le ici](https://brew.sh)

```bash
brew tap fparrav/livewalls
brew install livewalls
```

**Avantages de la méthode Homebrew :**
- ✅ Installation automatique sans configuration manuelle
- ✅ Aucun problème de quarantaine macOS  
- ✅ Mises à jour faciles avec `brew upgrade`

**📋 Note :** LiveWalls n'est pas dans le dépôt officiel Homebrew car il nécessite un certificat Apple Developer (99$/an) pour les apps signées. En tant que projet open source gratuit, nous utilisons un "tap" personnel qui permet la distribution sécurisée d'apps non signées.

### ⚠️ Important : Application Non Signée

**LiveWalls est un projet open source** et ne possède pas de certificat Apple Developer (99$/an).
Pour ouvrir l'application pour la première fois :

#### Méthode 1 : Commande Terminal (Recommandée)

```bash
sudo xattr -rd com.apple.quarantine /chemin/vers/LiveWalls.app
```

#### Méthode 2 : Réglages Système

1. Essayez d'ouvrir LiveWalls (un avertissement de sécurité apparaîtra)
2. Allez dans **Réglages Système** → **Confidentialité et Sécurité**
3. Cherchez "LiveWalls a été bloqué" et cliquez sur **"Ouvrir quand même"**

### 🛠️ Compiler depuis la Source

```bash
git clone https://github.com/fparrav/LiveWalls.git
cd LiveWalls
./build.sh
```

L'application compilée sera dans le dossier `build/Debug/`.

## 🔒 Sécurité et Confidentialité

**LiveWalls est un projet 100% open source** que vous pouvez examiner et compiler vous-même.

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

---

Fait avec ❤️ pour la communauté macOS
