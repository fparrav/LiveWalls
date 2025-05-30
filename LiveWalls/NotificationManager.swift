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
                print("Error al solicitar permisos de notificación: \(error.localizedDescription)")
            }
        }
    }
    
    func showWallpaperStarted(videoName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Live Walls"
        content.body = "Fondo de pantalla iniciado: \(videoName)"
        content.sound = nil // Sin sonido para no molestar
        
        let request = UNNotificationRequest(identifier: "wallpaper_started", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func showWallpaperStopped() {
        let content = UNMutableNotificationContent()
        content.title = "Live Walls"
        content.body = "Fondo de pantalla detenido"
        content.sound = nil
        
        let request = UNNotificationRequest(identifier: "wallpaper_stopped", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func showError(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Live Walls - Error"
        content.body = message
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: "error_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
