// PersistenceController.swift
import Foundation

struct PersistenceController {
    private let url: URL?
    private let inMemory: Bool
    
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        if inMemory {
            self.url = nil
        } else {
            let fm = FileManager.default
            let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true)
            let dir = appSupport?.appendingPathComponent("appMenu", isDirectory: true)
            if let dir, (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                self.url = dir.appendingPathComponent("items.json")
            } else {
                self.url = nil
            }
        }
    }
    
    func load() -> [LaunchItem]? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([LaunchItem].self, from: data)
            return decoded
        } catch {
            print("Load error: \(error)")
            return nil
        }
    }
    
    func save(_ items: [LaunchItem]) {
        guard let url else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Save error: \(error)")
        }
    }
}
