import Foundation

struct VideoFile: Identifiable, Codable, Hashable {
    let id: UUID
    var url: URL // Esta URL podría no ser accesible directamente después de reiniciar la app
    var name: String
    var thumbnailData: Data?
    var isActive: Bool = false
    var bookmarkData: Data? // Para acceso persistente a archivos

    init(id: UUID = UUID(), url: URL, name: String? = nil, thumbnailData: Data? = nil, isActive: Bool = false, bookmarkData: Data? = nil) {
        self.id = id
        self.url = url
        self.name = name ?? url.deletingPathExtension().lastPathComponent
        self.thumbnailData = thumbnailData
        self.isActive = isActive
        self.bookmarkData = bookmarkData // Asegurar que esta nueva propiedad se inicializa
    }

    // Para conformar con Codable, necesitamos manejar la URL de manera especial
    enum CodingKeys: String, CodingKey {
        case id, url, name, isActive, thumbnailData, bookmarkData // Añadir id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id) // Decodificar id
        self.url = try container.decode(URL.self, forKey: .url)
        self.name = try container.decode(String.self, forKey: .name)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        self.bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id) // Codificar id
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }

    static func == (lhs: VideoFile, rhs: VideoFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
