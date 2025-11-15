// SettingsView.swift
import SwiftUI
import UniformTypeIdentifiers
import AppKit

// Environment key to let nested rows trigger the shared import sheet in SettingsView.
private struct RequestImportKey: EnvironmentKey {
    static let defaultValue: (UUID?) -> Void = { _ in }
}

private extension EnvironmentValues {
    var requestImport: (UUID?) -> Void {
        get { self[RequestImportKey.self] }
        set { self[RequestImportKey.self] = newValue }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: UUID?
    @State private var newFolderName: String = ""
    
    // Import from /Applications state
    @State private var showingImportSheet = false
    @State private var importCandidates: [AppCandidate] = []
    @State private var importSelection = Set<UUID>()
    @State private var importFilter = ""
    // Optional: target parent to import into (nil = root). FolderRow will set this.
    @State private var importTargetParentID: UUID? = nil
    @State private var isScanning = false
    @State private var scanError: String?
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("Folders & Apps")
                        .font(.headline)
                    Spacer()
                    Button {
                        // Add a new folder at root; you could also target selection if desired.
                        store.addFolder(named: "New Folder")
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        let target = preferredTargetFolderID()
                        pickApplications { urls in
                            // Dedupe within this batch and against existing at target level
                            let existing = existingAppURLs(inParent: target)
                            var seen: Set<URL> = []
                            for url in urls {
                                let norm = url.standardizedFileURL
                                guard !existing.contains(norm), !seen.contains(norm) else { continue }
                                seen.insert(norm)
                                store.addApp(url, to: target)
                            }
                        }
                    } label: {
                        Label("Add Apps", systemImage: "plus.app")
                    }
                    Button {
                        // Prefer selected folder; else root "Applications" if present; else root.
                        let target = preferredTargetFolderID()
                        requestImport(to: target)
                    } label: {
                        Label("Import from /Applications…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isScanning)
                    Divider().frame(height: 20)
                    Button {
                        HelpManager.openHelp()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
                .padding(.bottom, 8)
                
                OutlineEditor(items: $store.items, selection: $selection)
                    // Allow FolderRow to present the same import UI, targeted at that folder
                    .environment(\.requestImport, { parentID in
                        requestImport(to: parentID)
                    })
                
                HStack {
                    Button(role: .destructive) {
                        if let id = selection { store.delete(itemID: id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }.disabled(selection == nil)
                    
                    Spacer()
                    
                    Button("Close") {
                        NSApp.keyWindow?.close()
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            .frame(minWidth: 520)
            .sheet(isPresented: $showingImportSheet) {
                ImportAppsSheet(
                    isScanning: $isScanning,
                    candidates: $importCandidates,
                    selection: $importSelection,
                    filter: $importFilter,
                    errorMessage: $scanError,
                    onAdd: { selected in
                        // Dedupe against existing apps at the target level and within the selection itself.
                        let targetParent = importTargetParentID
                        let existing = existingAppURLs(inParent: targetParent)
                        
                        var seen: Set<URL> = []
                        let toAdd = selected.filter { cand in
                            let norm = normalized(cand.url)
                            guard !existing.contains(norm), !seen.contains(norm) else { return false }
                            seen.insert(norm)
                            return true
                        }
                        
                        for candidate in toAdd {
                            store.addApp(candidate.url, displayName: candidate.name, to: targetParent)
                        }
                    }
                )
                .frame(minWidth: 560, minHeight: 480)
            }
        }
        .navigationViewStyle(.automatic)
    }
    
    // Choose where to add/import apps:
    // 1) If a folder is selected, target that folder.
    // 2) Else, if a root folder named "Applications" exists, target it.
    // 3) Else, add at root (nil).
    private func preferredTargetFolderID() -> UUID? {
        if let sel = selection, findFolder(id: sel, in: store.items) != nil {
            return sel
        }
        return rootFolderID(named: "Applications")
    }
    
    private func rootFolderID(named name: String) -> UUID? {
        for item in store.items {
            if case .folder(let f) = item, f.name == name {
                return f.id
            }
        }
        return nil
    }
    
    private func requestImport(to parentID: UUID?) {
        importTargetParentID = parentID
        startScanApplications()
    }
    
    private func startScanApplications() {
        isScanning = true
        scanError = nil
        importCandidates = []
        importSelection = []
        showingImportSheet = true
        
        Task {
            do {
                let urls = try await scanApplicationsInApplicationsFolder()
                let candidates = urls
                    .sorted(by: { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending })
                    .map { AppCandidate(name: displayName(for: $0), url: $0) }
                await MainActor.run {
                    self.importCandidates = candidates
                    self.importSelection = Set(candidates.map { $0.id }) // preselect all
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.scanError = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }
    
    // MARK: - Deduping helpers
    
    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL
    }
    
    private func existingAppURLs(inParent parentID: UUID?) -> Set<URL> {
        var urls: [URL] = []
        if let pid = parentID {
            if let folder = findFolder(id: pid, in: store.items) {
                for child in folder.children {
                    if case .app(let a) = child {
                        urls.append(normalized(a.url))
                    }
                }
            }
        } else {
            for item in store.items {
                if case .app(let a) = item {
                    urls.append(normalized(a.url))
                }
            }
        }
        return Set(urls)
    }
    
    private func findFolder(id: UUID, in items: [LaunchItem]) -> FolderItem? {
        for it in items {
            switch it {
            case .app:
                continue
            case .folder(let f):
                if f.id == id { return f }
                if let found = findFolder(id: id, in: f.children) {
                    return found
                }
            }
        }
        return nil
    }
}

// MARK: - Outline editor

private struct OutlineEditor: View {
    @EnvironmentObject private var store: AppStore
    @Binding var items: [LaunchItem]
    @Binding var selection: UUID?
    
    var body: some View {
        List(selection: $selection) {
            RecursiveItems(items: $items, parentID: nil)
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 24)
    }
}

private struct RecursiveItems: View {
    @EnvironmentObject private var store: AppStore
    @Binding var items: [LaunchItem]
    let parentID: UUID?
    
    var body: some View {
        ForEach($items, id: \.id) { $item in
            switch item {
            case .app(var app):
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    TextField("App Name", text: Binding(
                        get: { app.name },
                        set: { app.name = $0; item = .app(app) }
                    ))
                    Spacer()
                    Text(app.url.lastPathComponent)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Rename") { /* Inline via TextField */ }
                    Button("Remove", role: .destructive) { remove(item.id) }
                }
                .onDrag {
                    NSItemProvider(object: item.id.uuidString as NSString)
                }
            case .folder(var folder):
                FolderRow(
                    folder: folder,
                    itemBinding: $item,
                    childrenBinding: Binding(
                        get: { folder.children },
                        set: { folder.children = $0; item = .folder(folder) }
                    ),
                    parentID: parentID
                )
            }
        }
        // Drop BETWEEN rows within this level (root or folder) at a specific index
        .onInsert(of: [.plainText]) { index, providers in
            providers.loadFirstString { str in
                guard let draggedID = UUID(uuidString: str) else { return }
                
                // Prevent moving into own subtree (target parent cannot be a descendant of dragged)
                guard isValidMove(draggedID: draggedID, targetParentID: parentID) else {
                    NSSound.beep()
                    return
                }
                
                // Prevent no-op move: same parent and at the same spot
                if let loc = currentLocation(of: draggedID, in: store.items) {
                    if loc.parent == parentID {
                        if index == loc.index || index == loc.index + 1 {
                            NSSound.beep()
                            return
                        }
                    }
                }
                
                store.move(itemID: draggedID, toParent: parentID, at: index)
            }
        }
        .onMove(perform: moveLocal)
        .onDelete(perform: deleteLocal)
    }
    
    // Local reordering within the same level via Edit menu or drag handles
    private func moveLocal(from offsets: IndexSet, to destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
    }
    
    private func deleteLocal(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }
    
    private func remove(_ id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: idx)
        }
    }
    
    // MARK: - Cycle prevention helpers (use current snapshot from store)
    private func isValidMove(draggedID: UUID, targetParentID: UUID?) -> Bool {
        if let targetParentID, targetParentID == draggedID { return false }
        guard let targetParentID else { return true }
        return !isAncestor(ancestorID: draggedID, of: targetParentID, in: store.items)
    }
    
    private func isAncestor(ancestorID: UUID, of potentialDescendantID: UUID, in items: [LaunchItem]) -> Bool {
        guard let ancestorNode = findNode(id: ancestorID, in: items) else { return false }
        switch ancestorNode {
        case .app:
            return false
        case .folder(let f):
            return subtreeContains(items: f.children, id: potentialDescendantID)
        }
    }
    
    private func findNode(id: UUID, in items: [LaunchItem]) -> LaunchItem? {
        for it in items {
            if it.id == id { return it }
            if case .folder(let f) = it, let found = findNode(id: id, in: f.children) {
                return found
            }
        }
        return nil
    }
    
    private func subtreeContains(items: [LaunchItem], id: UUID) -> Bool {
        for it in items {
            if it.id == id { return true }
            if case .folder(let f) = it, subtreeContains(items: f.children, id: id) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Current location helper
    private func currentLocation(of id: UUID, in items: [LaunchItem]) -> (parent: UUID?, index: Int)? {
        for (idx, it) in items.enumerated() {
            if it.id == id {
                return (parent: parentID, index: idx)
            }
            if case .folder(let f) = it {
                if let result = currentLocation(of: id, in: f.children, parent: f.id) {
                    return result
                }
            }
        }
        return nil
    }
    
    private func currentLocation(of id: UUID, in items: [LaunchItem], parent: UUID?) -> (parent: UUID?, index: Int)? {
        for (idx, it) in items.enumerated() {
            if it.id == id {
                return (parent: parent, index: idx)
            }
            if case .folder(let f) = it, let found = currentLocation(of: id, in: f.children, parent: f.id) {
                return found
            }
        }
        return nil
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.requestImport) private var requestImport
    let folder: FolderItem
    @Binding var itemBinding: LaunchItem
    @Binding var childrenBinding: [LaunchItem]
    let parentID: UUID?
    
    @State private var isTargeted: Bool = false
    
    var body: some View {
        DisclosureGroup {
            // Children
            RecursiveItems(items: $childrenBinding, parentID: folder.id)
        } label: {
            HStack {
                Image(systemName: "folder")
                TextField("Folder Name", text: Binding(
                    get: { folder.name },
                    set: { newName in
                        var f = folder
                        f.name = newName
                        itemBinding = .folder(f)
                    }
                ))
                Spacer()
                Menu {
                    Button("Add Folder") {
                        var f = folder
                        f.children.append(.folder(FolderItem(name: "New Folder")))
                        itemBinding = .folder(f)
                    }
                    Button("Add Apps…") {
                        pickApplications { urls in
                            // Dedupe against current folder's direct children and within the picked set
                            var f = folder
                            var existing: Set<URL> = Set(
                                f.children.compactMap {
                                    if case .app(let a) = $0 { return a.url.standardizedFileURL }
                                    return nil
                                }
                            )
                            var seen: Set<URL> = []
                            for url in urls {
                                let norm = url.standardizedFileURL
                                // Skip if already exists in folder or already added in this batch
                                guard !existing.contains(norm), !seen.contains(norm) else { continue }
                                seen.insert(norm)
                                existing.insert(norm)
                                f.children.append(.app(AppItem(name: url.deletingPathExtension().lastPathComponent, url: url))
                                )
                            }
                            itemBinding = .folder(f)
                        }
                    }
                    Button("Choose from /Applications…") {
                        // Present the shared sheet, targeted at this folder
                        requestImport(folder.id)
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background(backgroundHighlight)
            // Drop ON the folder row to add as child (append)
            .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
                providers.loadFirstString { str in
                    guard let draggedID = UUID(uuidString: str) else { return }
                    
                    // Cycle prevention
                    guard isValidMove(draggedID: draggedID, targetParentID: folder.id) else {
                        NSSound.beep()
                        return
                    }
                    
                    // No-op prevention when appending: already last child in this folder
                    if let loc = currentLocation(of: draggedID, in: store.items) {
                        if loc.parent == folder.id {
                            let lastIndex = childrenBinding.count - 1
                            if lastIndex >= 0 && loc.index == lastIndex {
                                NSSound.beep()
                                return
                            }
                        }
                    }
                    
                    store.move(itemID: draggedID, toParent: folder.id, at: nil)
                }
                return true
            }
        }
        .onDrag {
            NSItemProvider(object: folder.id.uuidString as NSString)
        }
    }
    
    private var backgroundHighlight: some View {
        Group {
            if isTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.15))
            } else {
                Color.clear
            }
        }
    }
    
    // MARK: - Cycle prevention helpers
    private func isValidMove(draggedID: UUID, targetParentID: UUID?) -> Bool {
        if let targetParentID, targetParentID == draggedID { return false }
        guard let targetParentID else { return true }
        return !isAncestor(ancestorID: draggedID, of: targetParentID, in: store.items)
    }
    
    private func isAncestor(ancestorID: UUID, of potentialDescendantID: UUID, in items: [LaunchItem]) -> Bool {
        guard let ancestorNode = findNode(id: ancestorID, in: items) else { return false }
        switch ancestorNode {
        case .app:
            return false
        case .folder(let f):
            return subtreeContains(items: f.children, id: potentialDescendantID)
        }
    }
    
    private func findNode(id: UUID, in items: [LaunchItem]) -> LaunchItem? {
        for it in items {
            if it.id == id { return it }
            if case .folder(let f) = it, let found = findNode(id: id, in: f.children) {
                return found
            }
        }
        return nil
    }
    
    private func subtreeContains(items: [LaunchItem], id: UUID) -> Bool {
        for it in items {
            if it.id == id { return true }
            if case .folder(let f) = it, subtreeContains(items: f.children, id: id) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Current location helper (shared logic)
    private func currentLocation(of id: UUID, in items: [LaunchItem]) -> (parent: UUID?, index: Int)? {
        for (idx, it) in items.enumerated() {
            if it.id == id {
                return (parent: nil, index: idx)
            }
            if case .folder(let f) = it {
                if let found = currentLocation(of: id, in: f.children, parent: f.id) {
                    return found
                }
            }
        }
        return nil
    }
    
    private func currentLocation(of id: UUID, in items: [LaunchItem], parent: UUID?) -> (parent: UUID?, index: Int)? {
        for (idx, it) in items.enumerated() {
            if it.id == id {
                return (parent: parent, index: idx)
            }
            if case .folder(let f) = it, let found = currentLocation(of: id, in: f.children, parent: f.id) {
                return found
            }
        }
        return nil
    }
}

// App picker utility
func pickApplications(completion: @escaping ([URL]) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    if #available(macOS 12.0, *) {
        panel.allowedContentTypes = [UTType.application]
    } else {
        panel.allowedFileTypes = ["app"]
    }
    panel.begin { resp in
        if resp == .OK {
            completion(panel.urls)
        }
    }
}

// MARK: - Import from /Applications

private struct AppCandidate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
}

private func displayName(for url: URL) -> String {
    if let bundle = Bundle(url: url),
       let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
        return name
    }
    return url.deletingPathExtension().lastPathComponent
}

// Updated scanner: includes /Applications, /System/Applications and CoreServices
private func scanApplicationsInApplicationsFolder() async throws -> [URL] {
    let fm = FileManager.default
    let roots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true)
    ]
    
    var found: Set<URL> = []
    
    func enumerateApps(at base: URL) {
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                found.insert(url.standardizedFileURL)
            }
        }
    }
    
    for root in roots {
        if (try? root.checkResourceIsReachable()) == true {
            enumerateApps(at: root)
        }
    }
    
    return Array(found)
}

private struct ImportAppsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var isScanning: Bool
    @Binding var candidates: [AppCandidate]
    @Binding var selection: Set<UUID>
    @Binding var filter: String
    @Binding var errorMessage: String?
    
    var onAdd: (_ selected: [AppCandidate]) -> Void
    
    private var filteredCandidates: [AppCandidate] {
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.isEmpty { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(f) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(f) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Import from /Applications")
                    .font(.title3).bold()
                if isScanning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            
            HStack {
                TextField("Search", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("Select All") {
                    selection = Set(filteredCandidates.map { $0.id })
                }
                .disabled(filteredCandidates.isEmpty)
                Button("Select None") {
                    // Remove only the visible ones from selection
                    let visible = Set(filteredCandidates.map { $0.id })
                    selection.subtract(visible)
                }
                .disabled(selection.isEmpty)
            }
            
            List {
                ForEach(filteredCandidates, id: \.id) { candidate in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Toggle(isOn: Binding(
                            get: { selection.contains(candidate.id) },
                            set: { isOn in
                                if isOn {
                                    selection.insert(candidate.id)
                                } else {
                                    selection.remove(candidate.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                Text(candidate.url.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 22)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add Selected") {
                    let selected = candidates.filter { selection.contains($0.id) }
                    onAdd(selected)
                    dismiss()
                }
                .disabled(selection.isEmpty || isScanning)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

// MARK: - NSItemProvider helpers

private extension Array where Element == NSItemProvider {
    func loadFirstString(_ completion: @escaping (String) -> Void) {
        guard let provider = first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            if let nsstr = object as? NSString {
                let str = nsstr as String
                DispatchQueue.main.async {
                    completion(str)
                }
            }
        }
    }
}

