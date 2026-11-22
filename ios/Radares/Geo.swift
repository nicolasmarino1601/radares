import Foundation

/// Un punto (latitud, longitud) en grados.
struct LL: Equatable {
    var lat: Double
    var lon: Double
    init(_ lat: Double, _ lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

enum Geo {
    static let earthR = 6_371_000.0

    @inline(__always) static func rad(_ x: Double) -> Double { x * .pi / 180 }
    @inline(__always) static func deg(_ x: Double) -> Double { x * 180 / .pi }

    /// Distancia en metros (haversine).
    static func dist(_ a1: Double, _ o1: Double, _ a2: Double, _ o2: Double) -> Double {
        let dA = rad(a2 - a1), dO = rad(o2 - o1)
        let s = pow(sin(dA / 2), 2) + cos(rad(a1)) * cos(rad(a2)) * pow(sin(dO / 2), 2)
        return 2 * earthR * asin(min(1, sqrt(s)))
    }

    static func dist(_ a: LL, _ b: LL) -> Double { dist(a.lat, a.lon, b.lat, b.lon) }

    /// Rumbo inicial de a hacia b, en grados (0 a 360).
    static func bearing(_ a1: Double, _ o1: Double, _ a2: Double, _ o2: Double) -> Double {
        let y = sin(rad(o2 - o1)) * cos(rad(a2))
        let x = cos(rad(a1)) * sin(rad(a2)) - sin(rad(a1)) * cos(rad(a2)) * cos(rad(o2 - o1))
        return (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    static func bearing(_ a: LL, _ b: LL) -> Double { bearing(a.lat, a.lon, b.lat, b.lon) }

    /// Diferencia entre dos rumbos (0 a 180).
    static func adiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Punto a `d` metros de (a, o) con rumbo `brg`.
    static func dest(_ a: Double, _ o: Double, _ brg: Double, _ d: Double) -> LL {
        let dr = d / earthR, b = rad(brg), a1 = rad(a), o1 = rad(o)
        let a2 = asin(sin(a1) * cos(dr) + cos(a1) * sin(dr) * cos(b))
        let o2 = o1 + atan2(sin(b) * sin(dr) * cos(a1), cos(dr) - sin(a1) * sin(a2))
        return LL(deg(a2), deg(o2))
    }

    static func dest(_ p: LL, _ brg: Double, _ d: Double) -> LL { dest(p.lat, p.lon, brg, d) }

    /// Polilínea codificada de Google, precisión 5.
    static func decodePolyline(_ s: String) -> [LL] {
        let bytes = Array(s.utf8)
        var pts: [LL] = []
        var i = 0, lat = 0, lon = 0
        func next() -> Int? {
            var shift = 0, result = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 31) << shift
                shift += 5
                if b < 32 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            pts.append(LL(Double(lat) / 1e5, Double(lon) / 1e5))
        }
        return pts
    }

    struct Projection {
        var d: Double       // distancia del punto a la línea (m)
        var along: Double   // metros recorridos sobre la línea hasta la proyección
        var total: Double   // largo total de la línea (m)
        var segB: Double    // rumbo del segmento más cercano
        var index: Int
    }

    /// Proyección de un punto sobre una polilínea (aproximación plana local).
    static func project(_ lat: Double, _ lon: Double, _ pts: [LL]) -> Projection? {
        guard pts.count > 1 else { return nil }
        let k = cos(rad(lat)) * 111_320, m = 110_540.0
        var best: Projection? = nil
        var acc = 0.0
        for i in 0..<(pts.count - 1) {
            let ax = (pts[i].lon - lon) * k, ay = (pts[i].lat - lat) * m
            let bx = (pts[i + 1].lon - lon) * k, by = (pts[i + 1].lat - lat) * m
            let dx = bx - ax, dy = by - ay
            let l2 = dx * dx + dy * dy, l = sqrt(l2)
            var t = l2 > 0 ? -(ax * dx + ay * dy) / l2 : 0
            t = max(0, min(1, t))
            let x = ax + t * dx, y = ay + t * dy
            let d = sqrt(x * x + y * y)
            if best == nil || d < best!.d {
                let segB = (deg(atan2(dx, dy)) + 360).truncatingRemainder(dividingBy: 360)
                best = Projection(d: d, along: acc + t * l, total: 0, segB: segB, index: i)
            }
            acc += l
        }
        best?.total = acc
        return best
    }

    static func polyLen(_ pts: [LL]) -> Double {
        guard pts.count > 1 else { return 0 }
        var s = 0.0
        for i in 0..<(pts.count - 1) { s += dist(pts[i], pts[i + 1]) }
        return s
    }
}

enum Fmt {
    /// "350 m" / "1,2 km"
    static func km(_ m: Double) -> String {
        if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
        return String(format: "%.1f", m / 1000).replacingOccurrences(of: ".", with: ",") + " km"
    }

    /// Distancia para decir en voz alta.
    static func say(_ m: Double) -> String {
        if m < 1000 { return "\(max(50, Int((m / 50).rounded()) * 50)) metros" }
        var s = String(format: "%.1f", m / 1000).replacingOccurrences(of: ".", with: ",")
        if s.hasSuffix(",0") { s.removeLast(2) }
        return s + (s == "1" ? " kilómetro" : " kilómetros")
    }

    /// Número con coma decimal y sin ",0".
    static func num(_ x: Double) -> String {
        if x == x.rounded() { return String(Int(x)) }
        return String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",")
    }
}
