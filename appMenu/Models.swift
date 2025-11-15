// Models.swift
import Foundation

struct AppItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var url: URL
}

struct FolderItem: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var children: [LaunchItem] = []
}

enum LaunchItem: Hashable, Identifiable {
    case app(AppItem)
    case folder(FolderItem)
    
    var id: UUID {
        switch self {
        case .app(let a): return a.id
        case .folder(let f): return f.id
        }
    }
    
    var name: String {
        get {
            switch self {
            case .app(let a): return a.name
            case .folder(let f): return f.name
            }
        }
        set {
            switch self {
            case .app(var a):
                a.name = newValue
                self = .app(a)
            case .folder(var f):
                f.name = newValue
                self = .folder(f)
            }
        }
    }
    
    var children: [LaunchItem]? {
        switch self {
        case .app: return nil
        case .folder(let f): return f.children
        }
    }
    
    mutating func setChildren(_ newChildren: [LaunchItem]) {
        switch self {
        case .app:
            break
        case .folder(var f):
            f.children = newChildren
            self = .folder(f)
        }
    }
}

// Codable for LaunchItem (enum with associated values)
extension LaunchItem: Codable {
    private enum CodingKeys: String, CodingKey { case type, app, folder }
    private enum ItemType: String, Codable { case app, folder }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .app:
            let a = try container.decode(AppItem.self, forKey: .app)
            self = .app(a)
        case .folder:
            let f = try container.decode(FolderItem.self, forKey: .folder)
            self = .folder(f)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let a):
            try container.encode(ItemType.app, forKey: .type)
            try container.encode(a, forKey: .app)
        case .folder(let f):
            try container.encode(ItemType.folder, forKey: .type)
            try container.encode(f, forKey: .folder)
        }
    }
}
