// AppStore.swift
import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    // Root of the tree; supports nested folders
    @Published var items: [LaunchItem] = []
    
    // Notify non-SwiftUI components (status item) to rebuild menus
    var onModelChanged: (() -> Void)?
    
    private var cancellables: Set<AnyCancellable> = []
    private let persistence: PersistenceController
    private let seedFlagKey = "didSeedApps"
    
    init(inMemory: Bool = false) {
        self.persistence = PersistenceController(inMemory: inMemory)
        self.items = persistence.load() ?? AppStore.sampleData()
        
        // Persist and notify on changes
        $items
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] items in
                self?.persistence.save(items)
                self?.onModelChanged?()
            }
            .store(in: &cancellables)
        
        // Try seeding on first launch (or when there is no real data yet)
        seedApplicationsIfNeeded()
    }
    
    // Programmatic refresh (e.g., from UI button)
    func refreshMenusRequested() {
        onModelChanged?()
    }
    
    // CRUD helpers
    func addFolder(named name: String, to parentID: UUID? = nil) {
        let folder = FolderItem(name: name, children: [])
        insert(.folder(folder), intoParentWithID: parentID)
    }
    
    func addApp(_ url: URL, displayName: String? = nil, to parentID: UUID? = nil) {
        let name = displayName ?? url.deletingPathExtension().lastPathComponent
        let app = AppItem(name: name, url: url)
        insert(.app(app), intoParentWithID: parentID)
    }
    
    func rename(itemID: UUID, to newName: String) {
        mutateItem(withID: itemID) { item in
            item.name = newName
        }
    }
    
    func delete(itemID: UUID) {
        items = deleteItem(in: items, id: itemID)
    }
    
    func move(itemID: UUID, toParent parentID: UUID?, at index: Int? = nil) {
        guard var rootCopy = Optional(items),
              let extracted = extractItem(in: &rootCopy, id: itemID) else { return }
        items = rootCopy
        insert(extracted, intoParentWithID: parentID, at: index)
    }
    
    // MARK: - Tree utilities
    private func insert(_ item: LaunchItem, intoParentWithID parentID: UUID?, at index: Int? = nil) {
        if let pid = parentID {
            items = insertItem(in: items, item: item, intoParentWithID: pid, at: index)
        } else {
            var copy = items
            if let idx = index, idx <= copy.count {
                copy.insert(item, at: idx)
            } else {
                copy.append(item)
            }
            items = copy
        }
    }
    
    private func mutateItem(withID id: UUID, mutate: (inout LaunchItem) -> Void) {
        func mutateInArray(_ array: inout [LaunchItem]) -> Bool {
            for i in array.indices {
                if array[i].id == id {
                    mutate(&array[i])
                    return true
                }
                if case .folder(var f) = array[i] {
                    var children = f.children
                    if mutateInArray(&children) {
                        f.children = children
                        array[i] = .folder(f)
                        return true
                    }
                }
            }
            return false
        }
        var root = items
        if mutateInArray(&root) {
            items = root
        }
    }
    
    private func deleteItem(in array: [LaunchItem], id: UUID) -> [LaunchItem] {
        var out: [LaunchItem] = []
        for item in array {
            if item.id == id { continue }
            switch item {
            case .app:
                out.append(item)
            case .folder(var f):
                f.children = deleteItem(in: f.children, id: id)
                out.append(.folder(f))
            }
        }
        return out
    }
    
    private func extractItem(in array: inout [LaunchItem], id: UUID) -> LaunchItem? {
        for i in array.indices {
            if array[i].id == id {
                return array.remove(at: i)
            }
            if case .folder(var f) = array[i] {
                var children = f.children
                if let result = extractItem(in: &children, id: id) {
                    f.children = children
                    array[i] = .folder(f)
                    return result
                }
            }
        }
        return nil
    }
    
    private func insertItem(in array: [LaunchItem], item: LaunchItem, intoParentWithID parentID: UUID, at index: Int?) -> [LaunchItem] {
        var out: [LaunchItem] = []
        for it in array {
            switch it {
            case .app:
                out.append(it)
            case .folder(var f):
                if f.id == parentID {
                    if let idx = index, idx <= f.children.count {
                        f.children.insert(item, at: idx)
                    } else {
                        f.children.append(item)
                    }
                    out.append(.folder(f))
                } else {
                    f.children = insertItem(in: f.children, item: item, intoParentWithID: parentID, at: index)
                    out.append(.folder(f))
                }
            }
        }
        return out
    }
    
    // Sample data for first run (kept minimal)
    static func sampleData() -> [LaunchItem] {
        [
            .folder(FolderItem(name: "Browsers", children: [])),
            .folder(FolderItem(name: "Editors", children: []))
        ]
    }
    
    // MARK: - First-launch seeding
    private func seedApplicationsIfNeeded() {
        // If already seeded, do nothing
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: seedFlagKey) {
            return
        }
        
        // If user already has content (non-empty or has any apps), skip seeding
        if containsAnyApps(in: items) || items.contains(where: { $0.name == "Applications" }) {
            defaults.set(true, forKey: seedFlagKey)
            return
        }
        
        // Perform scan off the main thread, then update on main
        Task {
            let urls = await AppStore.scanApplicationsInApplicationsFolder()
            guard !urls.isEmpty else {
                defaults.set(true, forKey: seedFlagKey)
                return
            }
            
            let children: [LaunchItem] = urls
                .sorted(by: { AppStore.displayName(for: $0).localizedCaseInsensitiveCompare(AppStore.displayName(for: $1)) == .orderedAscending })
                .map { url in
                    .app(AppItem(name: AppStore.displayName(for: url), url: url))
                }
            
            let applicationsFolder = LaunchItem.folder(FolderItem(name: "Applications", children: children))
            
            // Insert at root, ahead of sample folders if they exist
            var newItems = items
            newItems.insert(applicationsFolder, at: 0)
            items = newItems
            
            defaults.set(true, forKey: seedFlagKey)
        }
    }
    
    private func containsAnyApps(in array: [LaunchItem]) -> Bool {
        for it in array {
            switch it {
            case .app:
                return true
            case .folder(let f):
                if containsAnyApps(in: f.children) { return true }
            }
        }
        return false
    }
    
    // MARK: - Utilities (scanning and display name)
    static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
    
    static func scanApplicationsInApplicationsFolder() async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let base = URL(fileURLWithPath: "/Applications", isDirectory: true)
                var found: [URL] = []
                
                if let enumerator = fm.enumerator(at: base,
                                                  includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let url as URL in enumerator {
                        if url.pathExtension.lowercased() == "app" {
                            found.append(url)
                        }
                    }
                }
                // Include /Applications/Utilities explicitly
                let utilities = base.appendingPathComponent("Utilities", isDirectory: true)
                if let enumerator = fm.enumerator(at: utilities,
                                                  includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let url as URL in enumerator {
                        if url.pathExtension.lowercased() == "app" {
                            found.append(url)
                        }
                    }
                }
                
                // Deduplicate
                let unique = Array(Set(found))
                continuation.resume(returning: unique)
            }
        }
    }
}
