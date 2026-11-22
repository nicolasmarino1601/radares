import Foundation

/// Tipos de radar puntual.
enum PointKind: String {
    case fixed = "F"            // radar fijo
    case trailer = "R"          // punto de radar remolque
    case mobileAnnounced = "MA" // radar móvil anunciado
    case mobileRecurring = "MR" // zona habitual de radar móvil
    case possible = "P"         // posible radar sin confirmar
    case redLight = "S"         // cámara de semáforo

    var label: String {
        switch self {
        case .fixed: return "Radar fijo"
        case .trailer: return "Posible radar remolque"
        case .mobileAnnounced: return "Radar móvil anunciado"
        case .mobileRecurring: return "Zona habitual de radar móvil"
        case .possible: return "Posible radar (sin confirmar)"
        case .redLight: return "Cámara de semáforo"
        }
    }
}

struct Approach {
    let bearing: Double
    let pts: [LL]
}

final class RadarPoint {
    let id: String
    let lat: Double
    let lon: Double
    let kind: PointKind
    let src: String
    let name: String
    let max: Int?
    let bear: Double?
    let aps: [Approach]?
    let err: Double
    let attr: String
    /// Tramos de velocidad media cuyo inicio o final está a menos de 200 m (la cabina del tramo).
    var nearT: [String] = []

    init(id: String, lat: Double, lon: Double, kind: PointKind, src: String, name: String,
         max: Int?, bear: Double?, aps: [Approach]?, err: Double, attr: String) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.kind = kind
        self.src = src
        self.name = name
        self.max = max
        self.bear = bear
        self.aps = aps
        self.err = err
        self.attr = attr
    }

    var ll: LL { LL(lat, lon) }
}

/// Un tramo de velocidad media, o un tramo con radares móviles de la DGT (`isZone`).
final class Stretch {
    let id: String
    let pts: [LL]
    let exact: Bool
    let name: String
    let road: String
    let max: Int?
    let src: String
    let len: Double
    let err: Double
    let attr: String
    let isZone: Bool
    var kmFrom: Double?
    var kmTo: Double?

    init(id: String, pts: [LL], exact: Bool, name: String, road: String, max: Int?, src: String,
         err: Double, attr: String, isZone: Bool) {
        self.id = id
        self.pts = pts
        self.exact = exact
        self.name = name
        self.road = road
        self.max = max
        self.src = src
        self.len = Geo.polyLen(pts)
        self.err = err
        self.attr = attr
        self.isZone = isZone
    }

    var a: LL { pts[0] }
    var b: LL { pts[pts.count - 1] }
}

struct Cell: Hashable {
    let i: Int
    let j: Int
}

struct DataCounts: CustomStringConvertible {
    var fixed = 0, tramos = 0, zones = 0, mobile = 0, trailer = 0, possible = 0, redLight = 0
    var pdfFixed = 0, pdfTramos = 0

    var description: String {
        "fijos \(fixed) · tramos \(tramos) · zonas \(zones) · móviles \(mobile) · remolque \(trailer) · posibles \(possible) · semáforos \(redLight) · (PDF: \(pdfFixed) fijos, \(pdfTramos) tramos)"
    }
}

final class RadarDB {
    static let cellSize = 0.05

    private(set) var points: [RadarPoint] = []
    private(set) var tramos: [Stretch] = []
    private(set) var zones: [Stretch] = []
    private var pGrid: [Cell: [RadarPoint]] = [:]
    private var sGrid: [Cell: [Stretch]] = [:]
    private(set) var counts = DataCounts()
    private(set) var suppDate = ""

    static func cellOf(_ la: Double, _ lo: Double) -> Cell {
        Cell(i: Int(floor(la / cellSize)), j: Int(floor(lo / cellSize)))
    }

    func queryPoints(_ la: Double, _ lo: Double, _ r: Int) -> [RadarPoint] {
        let c = RadarDB.cellOf(la, lo)
        var out: [RadarPoint] = []
        for i in -r...r {
            for j in -r...r {
                if let a = pGrid[Cell(i: c.i + i, j: c.j + j)] { out.append(contentsOf: a) }
            }
        }
        return out
    }

    func queryStretches(_ la: Double, _ lo: Double, _ r: Int) -> [Stretch] {
        let c = RadarDB.cellOf(la, lo)
        var seen = Set<ObjectIdentifier>()
        var out: [Stretch] = []
        for i in -r...r {
            for j in -r...r {
                guard let a = sGrid[Cell(i: c.i + i, j: c.j + j)] else { continue }
                for s in a where seen.insert(ObjectIdentifier(s)).inserted { out.append(s) }
            }
        }
        return out
    }

    private func addLine(_ s: Stretch) {
        var seen = Set<Cell>()
        let pts = s.pts
        for i in 0..<pts.count {
            let a = pts[i], b = i + 1 < pts.count ? pts[i + 1] : pts[i]
            let n = max(1, Int(ceil(Geo.dist(a, b) / 1500)))
            for j in 0...n {
                let la = a.lat + (b.lat - a.lat) * Double(j) / Double(n)
                let lo = a.lon + (b.lon - a.lon) * Double(j) / Double(n)
                let c = RadarDB.cellOf(la, lo)
                if seen.insert(c).inserted { sGrid[c, default: []].append(s) }
            }
        }
    }

    static func todayISO(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - construcción

    /// Arma la base a partir del feed de Radares Anunciados (`feed.geojson`), sus carreteras
    /// (`roads.json`) y el suplemento propio (`supp.json`). Cualquiera puede faltar.
    static func build(feed: [String: Any]?, roads: [String: Any]?, supp: [String: Any]?, today: String) -> RadarDB {
        let db = RadarDB()
        let rf = (roads?["features"] as? [String: Any]) ?? [:]
        let feats = (feed?["features"] as? [[String: Any]]) ?? []

        struct Key: Hashable { let x: Double; let y: Double }
        var ends = Set<Key>()
        for f in feats {
            guard let g = f["geometry"] as? [String: Any], (g["type"] as? String) == "LineString",
                  let c = g["coordinates"] as? [[Double]], c.count > 1,
                  c[0].count >= 2, c[c.count - 1].count >= 2 else { continue }
            ends.insert(Key(x: c[0][0], y: c[0][1]))
            ends.insert(Key(x: c[c.count - 1][0], y: c[c.count - 1][1]))
        }

        for f in feats {
            let p = (f["properties"] as? [String: Any]) ?? [:]
            guard let g = f["geometry"] as? [String: Any], let type = g["type"] as? String else { continue }
            if let active = p["active"] as? Bool, active == false { continue }
            let fid = idString(f["id"])
            let src = (p["source"] as? String) ?? ""
            let attr = (p["attribution"] as? String) ?? ""

            if type == "Point" {
                guard let c = g["coordinates"] as? [Double], c.count >= 2 else { continue }
                let kindRaw = (p["kind"] as? String) ?? ""
                if kindRaw == "section" && ends.contains(Key(x: c[0], y: c[1])) { continue } // cabina de un tramo
                if let vf = p["valid_from"] as? String, !vf.isEmpty, today < vf { continue }
                if let vt = p["valid_to"] as? String, !vt.isEmpty, today > vt { continue }
                let kind: PointKind
                switch kindRaw {
                case "trailer": kind = .trailer
                case "mobile_announced": kind = .mobileAnnounced
                case "mobile_recurring": kind = .mobileRecurring
                case "reported": kind = .possible
                default: kind = .fixed
                }
                var aps: [Approach]? = nil
                if let r = rf[fid] as? [String: Any], let arr = r["approaches"] as? [[String: Any]] {
                    let list: [Approach] = arr.compactMap { a in
                        guard let poly = a["polyline"] as? String else { return nil }
                        let pts = Geo.decodePolyline(poly)
                        guard pts.count > 1 else { return nil }
                        return Approach(bearing: num(a["bearing"]) ?? -1, pts: pts)
                    }
                    if !list.isEmpty { aps = list }
                }
                let bear = num(p["bearing"]).map(norm360) ?? numDir(p["direction"])
                var name = (p["name"] as? String) ?? ""
                if name.isEmpty { name = kind.label }
                let pt = RadarPoint(id: fid, lat: c[1], lon: c[0], kind: kind, src: src, name: name,
                                    max: speed(p["maxspeed"]), bear: bear, aps: aps, err: 0, attr: attr)
                db.points.append(pt)
                db.count(kind)
            } else if type == "LineString" {
                guard let coords = g["coordinates"] as? [[Double]] else { continue }
                var pts: [LL] = []
                var exact = false
                if let r = rf[fid] as? [String: Any], let line = r["line"] as? String {
                    let d = Geo.decodePolyline(line)
                    if d.count > 1 { pts = d; exact = true }
                }
                if !exact { pts = coords.compactMap { $0.count >= 2 ? LL($0[1], $0[0]) : nil } }
                guard pts.count > 1 else { continue }
                let isZone = src == "dgt_invive"
                let s = Stretch(id: fid, pts: pts, exact: exact, name: (p["name"] as? String) ?? "",
                                road: (p["road"] as? String) ?? "", max: speed(p["maxspeed"]), src: src,
                                err: 0, attr: attr, isZone: isZone)
                if isZone {
                    s.kmFrom = num(p["km_from"])
                    s.kmTo = num(p["km_to"])
                    db.zones.append(s)
                    db.counts.zones += 1
                } else {
                    db.tramos.append(s)
                    db.counts.tramos += 1
                }
            }
        }

        // ----- suplemento propio -----
        let date = (supp?["dgtDate"] as? String) ?? ""
        db.suppDate = date
        func near(_ la: Double, _ lo: Double, _ r: Double) -> Bool {
            db.points.contains { q in
                q.kind != .possible && abs(q.lat - la) < 0.01 && abs(q.lon - lo) < 0.013 && Geo.dist(q.lat, q.lon, la, lo) < r
            }
        }
        func str(_ x: [Any], _ i: Int) -> String { i < x.count ? ((x[i] as? String) ?? "") : "" }
        func dbl(_ x: [Any], _ i: Int) -> Double? { i < x.count ? num(x[i]) : nil }

        for (i, x) in ((supp?["F"] as? [[Any]]) ?? []).enumerated() {
            guard let la = dbl(x, 0), let lo = dbl(x, 1) else { continue }
            if near(la, lo, 150) { continue }
            let b = dbl(x, 2) ?? -1
            db.points.append(RadarPoint(
                id: "pdf\(i)", lat: la, lon: lo, kind: .fixed, src: "dgt_pdf", name: "Radar fijo " + str(x, 4),
                max: nil, bear: b >= 0 ? b : nil, aps: nil, err: dbl(x, 3) ?? 0,
                attr: "Listado oficial de cinemómetros de la DGT (\(date)), ubicado a partir de su punto kilométrico"))
            db.counts.fixed += 1
            db.counts.pdfFixed += 1
        }
        for (i, x) in ((supp?["M"] as? [[Any]]) ?? []).enumerated() {
            guard let la = dbl(x, 0), let lo = dbl(x, 1) else { continue }
            if near(la, lo, 120) { continue }
            let b = dbl(x, 3) ?? -1
            let mx = dbl(x, 2).flatMap { $0 > 0 ? Int($0) : nil }
            let at = str(x, 6)
            db.points.append(RadarPoint(
                id: "mun\(i)", lat: la, lon: lo, kind: .fixed, src: "municipal", name: str(x, 4),
                max: mx, bear: b >= 0 ? b : nil, aps: nil, err: dbl(x, 5) ?? 0,
                attr: at.isEmpty ? "Ayuntamiento" : at))
            db.counts.fixed += 1
        }
        for (i, x) in ((supp?["S"] as? [[Any]]) ?? []).enumerated() {
            guard let la = dbl(x, 0), let lo = dbl(x, 1) else { continue }
            if db.points.contains(where: { $0.kind == .redLight && Geo.dist($0.lat, $0.lon, la, lo) < 30 }) { continue }
            let b = dbl(x, 2) ?? -1
            let nm = str(x, 3)
            db.points.append(RadarPoint(
                id: "sem\(i)", lat: la, lon: lo, kind: .redLight, src: "osm_sem",
                name: nm.isEmpty ? "Cámara de semáforo" : nm, max: nil, bear: b >= 0 ? b : nil, aps: nil, err: 0,
                attr: "© colaboradores de OpenStreetMap (ODbL)"))
            db.counts.redLight += 1
        }
        for (i, x) in ((supp?["T"] as? [[Any]]) ?? []).enumerated() {
            guard let a1 = dbl(x, 0), let o1 = dbl(x, 1), let a2 = dbl(x, 2), let o2 = dbl(x, 3) else { continue }
            let label = str(x, 4)
            let road = label.split(separator: " ").first.map(String.init) ?? ""
            let mx = dbl(x, 7).flatMap { $0 > 0 ? Int($0) : nil }
            db.tramos.append(Stretch(
                id: "pdft\(i)", pts: [LL(a1, o1), LL(a2, o2)], exact: false, name: "Tramo " + label, road: road,
                max: mx, src: "dgt_pdf", err: dbl(x, 6) ?? 0,
                attr: "Listado oficial de cinemómetros de la DGT (\(date)), ubicado a partir de sus puntos kilométricos",
                isZone: false))
            db.counts.tramos += 1
            db.counts.pdfTramos += 1
        }

        // ----- índices -----
        for p in db.points { db.pGrid[cellOf(p.lat, p.lon), default: []].append(p) }
        for t in db.tramos { db.addLine(t) }
        for z in db.zones { db.addLine(z) }
        // cabinas al inicio o al final de un tramo: las anuncia el aviso del tramo
        for p in db.points where p.kind == .fixed {
            for s in db.queryStretches(p.lat, p.lon, 1) where !s.isZone {
                if Geo.dist(p.lat, p.lon, s.a.lat, s.a.lon) < 200 || Geo.dist(p.lat, p.lon, s.b.lat, s.b.lon) < 200 {
                    p.nearT.append(s.id)
                }
            }
        }
        return db
    }

    private func count(_ k: PointKind) {
        switch k {
        case .fixed: counts.fixed += 1
        case .trailer: counts.trailer += 1
        case .mobileAnnounced, .mobileRecurring: counts.mobile += 1
        case .possible: counts.possible += 1
        case .redLight: counts.redLight += 1
        }
    }
}

// MARK: - lectura tolerante del JSON

func num(_ v: Any?) -> Double? {
    if let d = v as? Double { return d.isFinite ? d : nil }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d.isFinite ? d : nil }
    return nil
}

private func norm360(_ x: Double) -> Double {
    let r = x.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

/// `direction` del feed: solo cuenta si es un rumbo numérico.
private func numDir(_ v: Any?) -> Double? {
    if let d = v as? Double { return d.isFinite ? norm360(d) : nil }
    guard let s = (v as? String)?.trimmingCharacters(in: .whitespaces),
          s.range(of: "^-?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil,
          let d = Double(s) else { return nil }
    return norm360(d)
}

private func speed(_ v: Any?) -> Int? {
    guard let d = num(v), d > 0 else { return nil }
    return Int(d.rounded())
}

private func idString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let d = num(v) { return d == d.rounded() ? String(Int(d)) : String(d) }
    return UUID().uuidString
}
