import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {
        requestNotificationPermission()
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Permisos de notificación concedidos")
            } else if let error = error {
                print("Notificaciones no disponibles: \(error.localizedDescription)")
            } else {
                print("Notificaciones no permitidas por el usuario")
            }
        }
    }
    
    func showWallpaperStarted(videoName: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("app_title", comment: "App title")
            content.body = String(format: NSLocalizedString("wallpaper_started_notification", comment: "Wallpaper started notification"), videoName)
            content.sound = nil // Sin sonido para no molestar
            
            let request = UNNotificationRequest(identifier: "wallpaper_started", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func showWallpaperStopped() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("app_title", comment: "App title")
            content.body = NSLocalizedString("wallpaper_stopped_notification", comment: "Wallpaper stopped notification")
            content.sound = nil
            
            let request = UNNotificationRequest(identifier: "wallpaper_stopped", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func showError(message: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("Error (sin notificación): \(message)")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = String(format: "%@ - %@", NSLocalizedString("app_title", comment: "App title"), NSLocalizedString("error_title", comment: "Error title"))
            content.body = message
            content.sound = UNNotificationSound.default
            
            let request = UNNotificationRequest(identifier: "error_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func showMessage(title: String, message: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("\(title): \(message)")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = nil // Sin sonido para mensajes informativos
            
            let request = UNNotificationRequest(identifier: "message_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
