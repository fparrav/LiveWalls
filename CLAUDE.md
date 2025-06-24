# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LiveWalls is a native macOS application for using videos as dynamic wallpapers. Built with Swift/SwiftUI, it allows users to set MP4/MOV videos as desktop backgrounds with smart scaling, multi-monitor support, and background execution.

## Common Development Commands

### Building & Running
- **Build:** `./build.sh build` or `xcodebuild build -project LiveWalls.xcodeproj -scheme LiveWalls`
- **Run:** `./build.sh run` (builds and executes with console logs)
- **Clean:** `./build.sh clean`
- **Archive:** `./build.sh archive` (creates release build)
- **Open in Xcode:** `open LiveWalls.xcodeproj`

### Testing
- **Run Tests:** `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls`
- **UI Tests:** Tests are located in `LiveWallsUITests/`
- **Unit Tests:** Tests are located in `LiveWallsTests/`

## Architecture Overview

### Core Components

1. **WallpaperManager** (`WallpaperManager.swift`)
   - Central manager for video wallpaper functionality
   - Handles video file management, security-scoped bookmarks, and desktop window creation
   - Thread-safe operations with concurrent queues and semaphores
   - Manages AVFoundation resources and memory cleanup

2. **DesktopVideoWindowMejorada** (`DesktopVideoWindowMejorada.swift`)
   - Custom NSWindow subclass for desktop-level video playback
   - Handles multi-screen support and video rendering
   - Manages window lifecycle and resource cleanup

3. **ScreenSaverManager** (`ScreenSaverManager.swift`)
   - Alternate implementation for screensaver-like functionality
   - Supports dynamic mode (animated only when locked) vs always-animated mode
   - Handles system events for screen sleep/wake

4. **VideoFile** (`VideoFile.swift`)
   - Model representing video files with metadata
   - Contains security-scoped bookmark data for sandboxed file access
   - Includes thumbnail generation and persistence

### UI Architecture

- **SwiftUI-based** with AppKit integration
- **ContentView**: Main interface with video grid and controls
- **StatusBarMenuView**: Menu bar controls for background operation
- **SettingsView**: Configuration panel for app preferences
- **LaunchManager**: Handles startup behavior and auto-launch

### Security & Permissions

- **App Sandbox enabled** with proper entitlements
- **Security-scoped bookmarks** for persistent file access
- **Accessibility permissions** required for system integration
- **Resource tracking** to prevent memory leaks with security-scoped URLs

## Development Guidelines

### Code Style (from Copilot instructions)
- **Comments in Spanish** for new/modified code
- **Variable/function names in Spanish** except for standard APIs
- **Comprehensive documentation** for public functions
- **Prefer structs for models, classes for managers**
- **Keep files under 500 lines** when possible

### Resource Management
- Always use security-scoped bookmarks for file access
- Properly release AVFoundation resources (players, layers, assets)
- Use concurrent queues with semaphores for thread safety
- Track and cleanup desktop windows on app termination

### Testing Requirements
- Test multi-monitor scenarios
- Verify resource cleanup and memory management
- Test file access with different permission states
- Validate UI updates with video state changes

## Key Technical Considerations

### Memory Management
- **Critical**: Proper cleanup of AVPlayer, AVPlayerLayer, and NSWindow instances
- Use weak references in closures to prevent retain cycles
- Security-scoped URLs must be stopped when no longer needed
- Desktop windows operate at system level and require careful lifecycle management

### Concurrency
- WallpaperManager uses `wallpaperOperationQueue` for thread-safe operations
- UI updates must happen on main queue
- Resource tracking uses concurrent queue with barriers

### Localization
- Supports 10 languages (EN, ES, FR, DE, IT, JA, KO, PT-BR, ZH-CN, ZH-TW)
- Localized strings in `Resources/Localizations/`
- Use `NSLocalizedString` for all user-facing text

### Platform Requirements
- **macOS 13.0+** (Sonoma preferred for optimal experience)
- **Xcode 15.0+** for development
- **Swift 5.7+** as specified in Package.swift

## Common Issues & Solutions

### Performance
- Video thumbnails are generated asynchronously to avoid UI blocking
- Desktop windows use `.ignoresCycle` to prevent system interference
- Memory pressure handled through proper resource deallocation

### Security
- All file access goes through security-scoped bookmarks
- Temporary files for wallpaper setting use system temp directory
- No sensitive data logging (use `.privacy` attributes)

### Multi-Screen Support
- Desktop windows created for each `NSScreen.screens`
- Window recreation on screen parameter changes
- Proper handling of screen connect/disconnect events

## Release Process

The project uses automated GitHub Actions for releases:
- **create-release.sh**: Script for creating release builds
- **DMG creation**: Automated packaging with background image
- **Version management**: Coordinated between Info.plist and build numbers