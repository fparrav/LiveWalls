# Gemini Workspace Context: LiveWalls

## Project Overview

LiveWalls is a native macOS application written in Swift using the SwiftUI framework. Its primary function is to allow users to set dynamic, video-based wallpapers on their desktop. The application is designed to be lightweight and accessible from the macOS status bar.

The project is structured as a standard Xcode project (`LiveWalls.xcodeproj`) and also includes a `Package.swift` file for better integration with Swift Package Manager and tools like the Swift Language Server in VS Code.

## Getting Started & Development

The primary development environment is Xcode. To begin, open the `LiveWalls.xcodeproj` file.

For command-line operations, a helper script `build.sh` is provided.

### Key Commands

*   **Build the app (Debug):**
    ```bash
    ./build.sh build
    ```
*   **Build and run the app:**
    ```bash
    ./build.sh run
    ```
    This command will also stream the application logs to the terminal.
*   **Clean the build folder:**
    ```bash
    ./build.sh clean
    ```
*   **Create a release archive:**
    ```bash
    ./build.sh archive
    ```

## Project Structure

*   `LiveWalls/`: Contains the core source code for the application.
    *   `LiveWallsApp.swift`: The main entry point of the application.
    *   `AppDelegate.swift`: Handles application lifecycle events.
    *   `ContentView.swift`: The main view of the application.
    *   `StatusBarMenuView.swift`: The view for the status bar menu.
    *   `WallpaperManager.swift`: The logic for managing the wallpaper.
    *   `Assets.xcassets`: Contains the application's assets (icons, colors, etc.).
    *   `*.lproj/`: Contains the localization files for different languages.
*   `LiveWalls.xcodeproj/`: The Xcode project file.
*   `build.sh`: A shell script for building, cleaning, running, and archiving the project.
*   `.github/workflows/release.yml`: GitHub Actions workflow for creating releases.

## Building and Releasing

The project uses GitHub Actions to automate the release process. The workflow is defined in `.github/workflows/release.yml`.

When a new tag matching the pattern `v*.*.*` is pushed to the repository, the workflow will:
1.  Build the application in Release mode.
2.  Create a `.dmg` disk image containing the application.
3.  Generate a changelog using `git-cliff`.
4.  Create a new GitHub Release with the `.dmg` file and the changelog.
