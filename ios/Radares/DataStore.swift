import Foundation

/// Descarga y guarda en el teléfono los radares de toda España.
final class DataStore {
    static let feedURL = URL(string: "https://geiserx.github.io/radares-anunciados-ha/feed.geojson")!
    static let roadsURL = URL(string: "https://geiserx.github.io/radares-anunciados-ha/roads.json")!
    static let maxAge: TimeInterval = 6 * 3600

    struct Loaded {
        var feed: Data?
        var roads: Data?
        var origin: String
        var date: Date?
        var error: String?
    }

    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("radares", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private var feedFile: URL { dir.appendingPathComponent("feed.geojson") }
    private var roadsFile: URL { dir.appendingPathComponent("roads.json") }

    var cacheDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: feedFile.path))?[.modificationDate] as? Date
    }

    var isStale: Bool {
        guard let d = cacheDate else { return true }
        return Date().timeIntervalSince(d) > DataStore.maxAge
    }

    /// Llama a `completion` en el hilo principal.
    func load(force: Bool, completion: @escaping (Loaded) -> Void) {
        let cachedFeed = try? Data(contentsOf: feedFile)
        let cachedRoads = try? Data(contentsOf: roadsFile)
        let cachedDate = cacheDate
        if !force, cachedFeed != nil, !isStale {
            completion(Loaded(feed: cachedFeed, roads: cachedRoads, origin: "guardados en el teléfono", date: cachedDate))
            return
        }
        fetch(DataStore.feedURL) { feed in
            guard let feed = feed, (try? JSONSerialization.jsonObject(with: feed)) != nil else {
                DispatchQueue.main.async {
                    if cachedFeed != nil {
                        completion(Loaded(feed: cachedFeed, roads: cachedRoads,
                                          origin: "guardados en el teléfono (sin conexión)", date: cachedDate))
                    } else {
                        completion(Loaded(feed: nil, roads: nil, origin: "solo los agregados a mano (sin conexión)", date: nil,
                                          error: "No se pudieron descargar los radares de toda España. Revisá la conexión y tocá «Actualizar radares» en Ajustes."))
                    }
                }
                return
            }
            self.fetch(DataStore.roadsURL) { roads in
                let roadsOK = roads.flatMap { (try? JSONSerialization.jsonObject(with: $0)) != nil ? $0 : nil }
                try? feed.write(to: self.feedFile, options: .atomic)
                if let r = roadsOK { try? r.write(to: self.roadsFile, options: .atomic) }
                DispatchQueue.main.async {
                    completion(Loaded(feed: feed, roads: roadsOK ?? cachedRoads, origin: "descargados de internet", date: Date()))
                }
            }
        }
    }

    private func fetch(_ url: URL, _ done: @escaping (Data?) -> Void) {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 40
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let h = resp as? HTTPURLResponse, h.statusCode == 200, let data = data, !data.isEmpty {
                done(data)
            } else {
                done(nil)
            }
        }.resume()
    }
}
