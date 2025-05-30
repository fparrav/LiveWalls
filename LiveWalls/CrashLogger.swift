import Foundation
import os.log

class CrashLogger {
    static let shared = CrashLogger()
    private let logger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")
    private let fileLogger: FileHandle?
    
    private init() {
        // Crear archivo de log
        let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveWalls_crash_log.txt")
        
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
        fileLogger = try? FileHandle(forWritingTo: logURL)
        
        log("🚀 CrashLogger iniciado - Log file: \(logURL.path)")
    }
    
    func log(_ message: String, level: OSLogType = .default) {
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        
        // Log a consola
        logger.log(level: level, "\(logMessage)")
        
        // Log a archivo
        if let data = "\(logMessage)\n".data(using: .utf8) {
            fileLogger?.write(data)
            fileLogger?.synchronizeFile()
        }
        
        // Log a terminal si está en debug
        #if DEBUG
        print("💾 \(logMessage)")
        #endif
    }
    
    func logMemoryState(_ context: String) {
        let memInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryMB = memInfo.resident_size / (1024 * 1024)
            log("📊 [\(context)] Memoria: \(memoryMB)MB", level: .info)
        }
    }
    
    func logCritical(_ message: String) {
        log("🚨 CRITICAL: \(message)", level: .fault)
        
        // Forzar flush inmediato
        fileLogger?.synchronizeFile()
    }
    
    deinit {
        fileLogger?.closeFile()
    }
}
