// File tray: park files on the island, drag them back out, or AirDrop them.
import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let key = "shelfItems"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: key) }

    func add(_ urls: [URL]) {
        for u in urls where u.isFileURL && !items.contains(u) { items.append(u) }
        save()
    }

    /// Accepts file drops from Finder or any app.
    func add(providers: [NSItemProvider]) {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items.removeAll(); save() }

    /// Drop out files that were moved or deleted since they were added.
    func prune() {
        let alive = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive != items { items = alive; save() }
    }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    static func urls(from providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var out: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); out.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(out) }
    }
}

struct FileThumb: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: url) {
                let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                    image = rep.nsImage
                }
            }
    }
}

struct ShelfView: View {
    @ObservedObject var shelf: Shelf
    @State private var airDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6))
                            Text("Drop files here to keep them handy").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                    )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s") · drag out to use")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Button("Clear") { shelf.clear() }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items, id: \.self) { url in tile(url) }
                        }
                    }
                }
            }
            airDropTile
        }
    }

    private func tile(_ url: URL) -> some View {
        VStack(spacing: 4) {
            FileThumb(url: url, size: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .frame(width: 74)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("AirDrop") { Shelf.airDrop([url]) }
            Divider()
            Button("Remove from Tray") { shelf.remove(url) }
        }
        .help(url.path)
    }

    private var airDropTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(airDropTargeted ? Color.black : Color.white)
            Text("AirDrop").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(airDropTargeted ? Color.black : Color.white.opacity(0.8))
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(airDropTargeted ? Color.white : Color(red: 0.1, green: 0.45, blue: 1).opacity(0.35)))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { Shelf.airDrop(shelf.items) }
        .onDrop(of: [.fileURL], isTargeted: $airDropTargeted) { providers in
            Shelf.urls(from: providers) { Shelf.airDrop($0) }
            return true
        }
        .help(shelf.items.isEmpty ? "Drop files here to AirDrop them" : "Click to AirDrop everything in the tray, or drop files here")
    }
}
