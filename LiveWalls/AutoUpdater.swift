import Foundation
import SwiftUI

/// Manager para notificaciones de actualizaciones desde GitHub
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
    
    /// Verifica si hay actualizaciones disponibles
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
                    print("✅ Nueva versión disponible: \(latestRelease.tagName)")
                } else {
                    print("✅ Aplicación actualizada o versión ignorada (v\(self.currentVersion))")
                }
                self.isChecking = false
            }
        } catch {
            await MainActor.run {
                self.isChecking = false
            }
            print("❌ Error verificando actualizaciones: \(error.localizedDescription)")
        }
    }
    
    /// Abre el release en GitHub
    func openRelease() {
        guard let release = updateInfo else { return }
        let releaseURL = "https://github.com/\(repoOwner)/\(repoName)/releases/tag/\(release.tagName)"
        if let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Marca la versión para no recordar más
    func skipVersion() {
        guard let release = updateInfo else { return }
        userDefaults.set(release.tagName, forKey: "SkippedVersion")
        updateAvailable = false
    }
    
    /// Muestra el diálogo de actualización
    func showUpdateDialog() {
        guard let release = updateInfo else { return }
        
        let alert = NSAlert()
        alert.messageText = "Nueva Versión Disponible"
        alert.informativeText = "LiveWalls \(release.tagName) está disponible.\nActual: \(currentVersion)\n\n\(release.name)"
        alert.addButton(withTitle: "Ver en GitHub")
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "No recordar esta versión")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            openRelease()
        case .alertThirdButtonReturn:
            skipVersion()
        default:
            break // Cancelar
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "\(gitHubAPI)/\(repoOwner)/\(repoName)/releases/latest")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
    
    private func shouldNotifyUpdate(for remoteVersion: String) -> Bool {
        // Verificar si es una versión más nueva
        guard isNewerVersion(remote: remoteVersion, current: currentVersion) else {
            return false
        }
        
        // Verificar si el usuario marcó que no quiere recordar esta versión
        let skippedVersion = userDefaults.string(forKey: "SkippedVersion")
        return skippedVersion != remoteVersion
    }
    
    private func isNewerVersion(remote: String, current: String) -> Bool {
        let remoteComponents = parseVersion(remote)
        let currentComponents = parseVersion(current)
        
        // Comparar major.minor.patch
        for i in 0..<3 {
            let remoteNum = i < remoteComponents.count ? remoteComponents[i] : 0
            let currentNum = i < currentComponents.count ? currentComponents[i] : 0
            
            if remoteNum > currentNum {
                return true
            } else if remoteNum < currentNum {
                return false
            }
        }
        
        return false // Versiones iguales
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

