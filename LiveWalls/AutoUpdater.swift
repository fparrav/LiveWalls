import Foundation
import SwiftUI

/// Manager for update notifications from GitHub
class UpdateNotifier: ObservableObject {
    @Published var updateAvailable = false
    @Published var updateInfo: GitHubRelease?
    @Published var isChecking = false
    
    private let gitHubAPI = "https://api.github.com/repos"
    private let repoOwner: String
    private let repoName: String
    let currentVersion: String
    
    private let session = URLSession.shared
    private let userDefaults = UserDefaults.standard
    
    init(repoOwner: String, repoName: String, currentVersion: String) {
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.currentVersion = currentVersion
    }
    
    /// Checks if updates are available
    func checkForUpdates() async {
        await MainActor.run {
            isChecking = true
            updateAvailable = false
        }
        
        do {
            let latestRelease = try await fetchLatestRelease()
            
            await MainActor.run {
                if self.shouldNotifyUpdate(for: latestRelease.tagName) {
                    self.updateInfo = latestRelease
                    self.updateAvailable = true
                    print("✅ New version available: \(latestRelease.tagName)")
                } else {
                    print("✅ Application up to date or version ignored (v\(self.currentVersion))")
                }
                self.isChecking = false
            }
        } catch {
            await MainActor.run {
                self.isChecking = false
            }
            print("❌ Error checking for updates: \(error.localizedDescription)")
        }
    }
    
    /// Opens the release on GitHub
    func openRelease() {
        guard let release = updateInfo else { return }
        let releaseURL = "https://github.com/\(repoOwner)/\(repoName)/releases/tag/\(release.tagName)"
        if let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Marks the version to not remind again
    func skipVersion() {
        guard let release = updateInfo else { return }
        userDefaults.set(release.tagName, forKey: "SkippedVersion")
        updateAvailable = false
    }
    
    /// Shows the update dialog
    func showUpdateDialog() {
        guard let release = updateInfo else { return }
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update_available_title", comment: "Update available dialog title")
        alert.informativeText = String(format: NSLocalizedString("update_available_message", comment: "Update available dialog message"), release.tagName, currentVersion, release.name)
        alert.addButton(withTitle: NSLocalizedString("view_on_github", comment: "View on GitHub button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.addButton(withTitle: NSLocalizedString("dont_remind_version", comment: "Don't remind for this version button"))
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            openRelease()
        case .alertThirdButtonReturn:
            skipVersion()
        default:
            break // Cancel
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "\(gitHubAPI)/\(repoOwner)/\(repoName)/releases/latest")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
    
    private func shouldNotifyUpdate(for remoteVersion: String) -> Bool {
        // Check if it's a newer version
        guard isNewerVersion(remote: remoteVersion, current: currentVersion) else {
            return false
        }
        
        // Check if the user marked not to be reminded of this version
        let skippedVersion = userDefaults.string(forKey: "SkippedVersion")
        return skippedVersion != remoteVersion
    }
    
    private func isNewerVersion(remote: String, current: String) -> Bool {
        let remoteComponents = parseVersion(remote)
        let currentComponents = parseVersion(current)
        
        // Compare major.minor.patch
        for i in 0..<3 {
            let remoteNum = i < remoteComponents.count ? remoteComponents[i] : 0
            let currentNum = i < currentComponents.count ? currentComponents[i] : 0
            
            if remoteNum > currentNum {
                return true
            } else if remoteNum < currentNum {
                return false
            }
        }
        
        return false // Equal versions
    }
    
    private func parseVersion(_ version: String) -> [Int] {
        let cleanVersion = version.replacingOccurrences(of: "v", with: "")
        return cleanVersion.split(separator: ".").compactMap { Int($0) }
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let id: Int
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case id, name, body, assets
        case tagName = "tag_name"
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Codable {
    let id: Int
    let name: String
    let size: Int
    let downloadCount: Int
    let downloadURL: URL
    
    enum CodingKeys: String, CodingKey {
        case id, name, size
        case downloadCount = "download_count"
        case downloadURL = "browser_download_url"
    }
}

