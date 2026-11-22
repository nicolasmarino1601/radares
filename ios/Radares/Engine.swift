import Foundation

// MARK: - ajustes

struct Settings: Codable, Equatable {
    var voice = true
    var zonas = true
    var moviles = true
    var posibles = true
    var remolque = true
    var sem = true
    var dist: Double = 0      // 0 = automática según la velocidad
    var simx: Double = 3
    var keepAwake = true
    var passed = true         // avisar al dejar atrás un radar o una zona de móviles

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voice = try c.decodeIfPresent(Bool.self, forKey: .voice) ?? true
        zonas = try c.decodeIfPresent(Bool.self, forKey: .zonas) ?? true
        moviles = try c.decodeIfPresent(Bool.self, forKey: .moviles) ?? true
        posibles = try c.decodeIfPresent(Bool.self, forKey: .posibles) ?? true
        remolque = try c.decodeIfPresent(Bool.self, forKey: .remolque) ?? true
        sem = try c.decodeIfPresent(Bool.self, forKey: .sem) ?? true
        dist = try c.decodeIfPresent(Double.self, forKey: .dist) ?? 0
        simx = try c.decodeIfPresent(Double.self, forKey: .simx) ?? 3
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        passed = try c.decodeIfPresent(Bool.self, forKey: .passed) ?? true
    }

    /// Si un radar puntual entra en los avisos con estos ajustes.
    func shows(_ p: RadarPoint) -> Bool {
        switch p.kind {
        case .redLight: return sem
        case .trailer: return remolque
        case .mobileAnnounced, .mobileRecurring: return moviles
        case .possible: return posibles
        case .fixed: return true
        }
    }
}

// MARK: - lo que se muestra en pantalla

struct AlertInfo: Equatable {
    var kindText: String
    var label: String
    var distance: Double
    var max: Int?
    var over: Bool
}

struct TramoInfo: Equatable {
    var title: String
    var avg: Double
    var max: Int?
    var progress: Double
    var progressText: String
    var hint: String
    var over: Bool
    var finished: Bool
}

struct ZoneInfo: Equatable {
    var label: String
}

struct EngineOutput: Equatable {
    var kmh: Double = 0
    var alert: AlertInfo?
    var tramo: TramoInfo?
    var zone: ZoneInfo?
    var next: String = ""
    var over = false
    /// "Radar superado", etc., unos segundos después de pasarlo.
    var passed: String?
}

// MARK: - motor de avisos

final class Engine {
    var db: RadarDB
    var settings: Settings
    /// (texto, cantidad de pitidos)
    var speak: (String, Int) -> Void

    private final class Alerted {
        var t: Double
        var p: RadarPoint
        var lim: Double
        var stage: Int
        var minD = Double.infinity  // lo más cerca que estuvimos (por la carretera)
        var silent = false          // cabina de un tramo: el aviso es el del tramo
        var passed = false
        init(t: Double, p: RadarPoint, lim: Double, stage: Int) {
            self.t = t
            self.p = p
            self.lim = lim
            self.stage = stage
        }
    }

    private struct ActiveTramo {
        let tr: Stretch
        let fwd: Bool
        let end: LL
        let t0: Double
        var dist: Double
        var nearEnd: Bool
        var minB: Double
        var over: Bool
    }

    private var last: (lat: Double, lon: Double, t: Double)?
    private(set) var heading: Double?
    private var alerted: [String: Alerted] = [:]
    private var tramo: ActiveTramo?
    private var tAlerted: [String: Double] = [:]
    private var zone: Stretch?
    private var zAlerted: [String: Double] = [:]
    private var zOut = 0
    private var lastAvgWarn: Double = -1e12
    private var tramoCard: TramoInfo?
    private var tramoCardUntil: Double = 0
    private var passedText: String?
    private var passedUntil: Double = 0
    private var lastPassT: Double = -1e12

    init(db: RadarDB, settings: Settings, speak: @escaping (String, Int) -> Void) {
        self.db = db
        self.settings = settings
        self.speak = speak
    }

    func reset() {
        last = nil
        heading = nil
        alerted = [:]
        tramo = nil
        tAlerted = [:]
        zone = nil
        zAlerted = [:]
        zOut = 0
        lastAvgWarn = -1e12
        tramoCard = nil
        tramoCardUntil = 0
        passedText = nil
        passedUntil = 0
        lastPassT = -1e12
    }

    func warnDist(_ v: Double) -> Double {
        settings.dist > 0 ? settings.dist : max(350, min(1000, v * 22))
    }

    /// Una posición nueva. `speed` en m/s, `heading` en grados, `t` en segundos.
    @discardableResult
    func onFix(lat: Double, lon: Double, speed: Double?, heading hdg: Double?, accuracy: Double?, t: Double) -> EngineOutput {
        let prev = last
        var v: Double? = nil
        if let s = speed, s >= 0, s.isFinite { v = s }
        if v == nil, let pr = prev {
            let dt = t - pr.t
            if dt > 0 { v = Geo.dist(pr.lat, pr.lon, lat, lon) / dt }
        }
        let vv = v ?? 0
        if let h = hdg, h >= 0, h.isFinite, vv > 1.5 {
            heading = h
        } else if let pr = prev, Geo.dist(pr.lat, pr.lon, lat, lon) > 12, vv > 1.5 {
            heading = Geo.bearing(pr.lat, pr.lon, lat, lon)
        }
        if tramo != nil, let pr = prev, accuracy == nil || accuracy! < 60 {
            tramo!.dist += Geo.dist(pr.lat, pr.lon, lat, lon)
        }
        last = (lat, lon, t)
        var out = EngineOutput()
        out.kmh = vv * 3.6
        evaluate(lat, lon, vv, t, &out)
        return out
    }

    /// Distancia efectiva a un radar puntual en el sentido de la marcha (o nil si no corresponde).
    private func pointDistance(_ p: RadarPoint, _ lat: Double, _ lon: Double, _ h: Double?, _ wd: Double) -> Double? {
        guard let h = h else { return nil }
        // 1) por la carretera (aproximaciones de roads.json)
        if let aps = p.aps {
            var best: Double? = nil
            for ap in aps {
                guard let pr = Geo.project(lat, lon, ap.pts), pr.d < 35, Geo.adiff(h, pr.segB) < 50 else { continue }
                let rem = pr.total - pr.along
                if rem >= -30 && (best == nil || rem < best!) { best = max(0, rem) }
            }
            if let b = best { return b }
        }
        // 2) en línea recta, adelante y en el sentido vigilado
        let d = Geo.dist(lat, lon, p.lat, p.lon)
        let br = Geo.bearing(lat, lon, p.lat, p.lon)
        if p.err > 0 { // ubicación aproximada: zona más amplia
            if d > p.err + wd { return nil }
            if d > p.err && Geo.adiff(h, br) > 45 { return nil }
            if let pb = p.bear, Geo.adiff(h, pb) > 80 { return nil }
            return max(0, d - p.err)
        }
        let lim = p.aps != nil ? 250.0 : 1e9 // con camino conocido, la recta solo cuenta muy cerca
        if d > lim { return nil }
        if Geo.adiff(h, br) >= (d < 250 ? 65 : 35) { return nil }
        if let pb = p.bear, Geo.adiff(h, pb) >= 70 { return nil }
        return d
    }

    private func evaluate(_ lat: Double, _ lon: Double, _ v: Double, _ t: Double, _ out: inout EngineOutput) {
        let kmh = v * 3.6, h = heading, wd = warnDist(v)
        let candP = db.queryPoints(lat, lon, 1)
        let candS = db.queryStretches(lat, lon, 1)
        tramoLogic(lat, lon, v, t, wd, candS, &out)

        // ¿dejamos atrás algún radar ya avisado?
        var passedNow: RadarPoint? = nil
        if let h = h {
            for (_, a) in alerted where !a.passed {
                let cur = pointDistance(a.p, lat, lon, h, wd)
                if let c = cur { a.minD = min(a.minD, c) }
                guard a.minD <= 80 else { continue } // nunca estuvimos cerca: no lo pasamos
                let straight = Geo.dist(lat, lon, a.p.lat, a.p.lon)
                let behind = Geo.adiff(h, Geo.bearing(lat, lon, a.p.lat, a.p.lon)) > 100
                if (cur == nil || cur! > a.minD + 40) && straight > 25 + a.p.err && behind {
                    a.passed = true
                    if !a.silent && passedNow == nil { passedNow = a.p }
                }
            }
        }
        var best: (p: RadarPoint, d: Double, lim: Double)? = nil
        for p in candP where settings.shows(p) && alerted[p.id]?.passed != true {
            guard let d = pointDistance(p, lat, lon, h, wd) else { continue }
            let lim = p.kind == .redLight ? 300 : wd
            if d <= max(lim, 1) * 1.6 && (best == nil || d < best!.d) { best = (p, d, lim) }
        }
        for (id, a) in alerted {
            let d = Geo.dist(lat, lon, a.p.lat, a.p.lon)
            if d > a.lim + a.p.err + 800 || t - a.t > 300 { alerted[id] = nil }
        }
        var spoke = false
        if let b = best {
            let p = b.p, d = b.d, lim = b.lim
            var a = alerted[p.id]
            if a == nil {
                // el mismo radar publicado dos veces: no repetir el aviso
                for (_, other) in alerted where Geo.dist(other.p.lat, other.p.lon, p.lat, p.lon) < 120 {
                    let c = Alerted(t: other.t, p: p, lim: other.lim, stage: other.stage)
                    c.silent = other.silent
                    c.passed = other.passed
                    alerted[p.id] = c
                    a = c
                    break
                }
            }
            if a == nil && d <= lim && p.nearT.contains(where: { tAlerted[$0] != nil || tramo?.tr.id == $0 }) {
                let c = Alerted(t: t, p: p, lim: lim, stage: 1) // cabina de un tramo ya anunciado
                c.silent = true
                alerted[p.id] = c
            } else if a == nil && d <= lim {
                alerted[p.id] = Alerted(t: t, p: p, lim: lim, stage: 1)
                var txt: String
                if p.err > 0 {
                    txt = "Radar fijo, ubicación aproximada, en los próximos \(Fmt.say(d + p.err * 2))."
                } else {
                    switch p.kind {
                    case .fixed: txt = "Radar fijo a \(Fmt.say(d))."
                    case .trailer: txt = "Posible radar remolque a \(Fmt.say(d))."
                    case .mobileAnnounced: txt = "Radar móvil anunciado para hoy a \(Fmt.say(d))."
                    case .mobileRecurring: txt = "Zona habitual de radar móvil a \(Fmt.say(d))."
                    case .possible: txt = "Posible radar, sin confirmar, a \(Fmt.say(d))."
                    case .redLight: txt = "Cámara de semáforo a \(Fmt.say(d))."
                    }
                }
                if let m = p.max { txt += " Límite \(m)." }
                speak(txt, 1)
                spoke = true
            } else if let al = a, al.stage == 1, let m = p.max, d <= 220, kmh > Double(m) + 2 {
                al.stage = 2
                speak("Atención. Vas a \(Int(kmh.rounded())). Límite \(m).", 2)
                spoke = true
            }
            let over = p.max.map { kmh > Double($0) + 2 } ?? false
            let label = p.name.replacingOccurrences(of: "^Radar (fijo|de tramo) ", with: "", options: .regularExpression)
            out.alert = AlertInfo(kindText: p.err > 0 ? "Radar fijo · ubicación aproximada" : p.kind.label,
                                  label: label, distance: d, max: p.max, over: over)
        }

        if let p = passedNow {
            let txt = p.kind == .redLight ? "Cámara superada" : (p.err > 0 ? "Zona del radar superada" : "Radar superado")
            showPassed(txt, t)
            if settings.passed && !spoke && t - lastPassT > 8 {
                lastPassT = t
                speak(txt + ".", 0)
            }
        }

        zoneLogic(lat, lon, t, candS, &out)
        if out.alert == nil, settings.passed, let txt = passedText, t < passedUntil { out.passed = txt }

        // próximo radar en la dirección de marcha
        if tramo == nil {
            if best != nil {
                out.next = ""
            } else if let h = h {
                var nx: (p: RadarPoint, d: Double)? = nil
                for it in db.queryPoints(lat, lon, 3) where settings.shows(it) && it.kind != .possible {
                    let d = Geo.dist(lat, lon, it.lat, it.lon)
                    if d > 15000 { continue }
                    if Geo.adiff(h, Geo.bearing(lat, lon, it.lat, it.lon)) > 30 { continue }
                    if let pb = it.bear, Geo.adiff(h, pb) > 70 { continue }
                    if nx == nil || d < nx!.d { nx = (it, d) }
                }
                if let n = nx {
                    out.next = "Próximo en tu dirección: \(n.p.name) · \(Fmt.km(n.d))"
                } else {
                    out.next = "Sin radares conocidos en los próximos 15 km de tu dirección."
                }
            } else {
                out.next = "Empezá a moverte para saber tu dirección."
            }
        }
        let overPoint = best.map { b in b.p.max.map { kmh > Double($0) + 2 } ?? false } ?? false
        out.over = overPoint || (tramo?.over ?? false)
    }

    private func showPassed(_ text: String, _ t: Double) {
        passedText = text
        passedUntil = t + 6
    }

    // MARK: tramos con radares móviles de la DGT

    private func zoneLogic(_ lat: Double, _ lon: Double, _ t: Double, _ cand: [Stretch], _ out: inout EngineOutput) {
        guard settings.zonas else {
            zone = nil
            return
        }
        var inZ: (z: Stretch, d: Double)? = nil
        for it in cand where it.isZone {
            guard let pr = Geo.project(lat, lon, it.pts) else { continue }
            let tol = it.exact ? 45.0 : 250.0
            if pr.d < tol && (inZ == nil || pr.d < inZ!.d) { inZ = (it, pr.d) }
        }
        if let iz = inZ {
            zOut = 0
            if zone == nil || zone!.id != iz.z.id {
                let prevSame = zone != nil && !zone!.road.isEmpty && zone!.road == iz.z.road
                zone = iz.z
                let lastT = zAlerted[iz.z.id]
                if !prevSame && (lastT == nil || t - lastT! > 1800) {
                    zAlerted[iz.z.id] = t
                    speak("Tramo con radares móviles de la Guardia Civil" + (iz.z.road.isEmpty ? "" : " en la \(iz.z.road)") + ".", 1)
                }
            }
        } else if let z = zone {
            zOut += 1
            if zOut >= 4 {
                zone = nil
                if settings.passed {
                    showPassed("Fin del tramo con radares móviles" + (z.road.isEmpty ? "" : " (\(z.road))"), t)
                    speak("Fin del tramo con radares móviles.", 0)
                }
            }
        }
        if let z = zone {
            var label = z.road
            if let a = z.kmFrom { label += " · km \(Fmt.num(a)) a \(Fmt.num(z.kmTo ?? a))" }
            out.zone = ZoneInfo(label: label)
        }
    }

    // MARK: tramos de velocidad media

    private func tramoLogic(_ lat: Double, _ lon: Double, _ v: Double, _ t: Double, _ wd: Double,
                            _ cand: [Stretch], _ out: inout EngineOutput) {
        if tramo == nil {
            if let h = heading {
                outer: for it in cand where !it.isZone {
                    for (idx, pair) in [(it.a, it.b), (it.b, it.a)].enumerated() {
                        let (A, B) = pair
                        let dA = Geo.dist(lat, lon, A.lat, A.lon), dB = Geo.dist(lat, lon, B.lat, B.lon)
                        let tol = 150 + it.err
                        if dA <= wd + it.err && dB > dA && Geo.adiff(h, Geo.bearing(lat, lon, A.lat, A.lon)) < 40 && tAlerted[it.id] == nil {
                            tAlerted[it.id] = t
                            if it.err > 500 {
                                speak("Tramo de velocidad media cerca, ubicación aproximada.", 1)
                            } else {
                                speak("Tramo de velocidad media a \(Fmt.say(max(0, dA - it.err)))." + (it.max.map { " Límite \($0)." } ?? ""), 1)
                            }
                        }
                        if it.err <= 500 && dA < tol && dB > it.len * 0.5 && Geo.adiff(h, Geo.bearing(lat, lon, B.lat, B.lon)) < 60 {
                            tramo = ActiveTramo(tr: it, fwd: idx == 0, end: B, t0: t, dist: 0, nearEnd: false, minB: dB, over: false)
                            tAlerted[it.id] = t
                            speak("Empieza el tramo de velocidad media." + (it.max.map { " Límite \($0)." } ?? ""), 2)
                            break outer
                        }
                    }
                }
            }
            for (id, tt) in tAlerted where t - tt > 600 { tAlerted[id] = nil }
            if tramo == nil, let c = tramoCard, t < tramoCardUntil { out.tramo = c }
            return
        }

        guard var s = tramo else { return }
        let tr = s.tr
        var dB = Geo.dist(lat, lon, s.end.lat, s.end.lon)
        if tr.exact, let pr = Geo.project(lat, lon, tr.pts), pr.d < 60 {
            dB = s.fwd ? pr.total - pr.along : pr.along
        }
        let el = t - s.t0
        let avg = el > 3 ? s.dist / el * 3.6 : v * 3.6
        s.over = tr.max.map { avg > Double($0) } ?? false
        let total = s.dist + dB
        var hint = ""
        if let m = tr.max, s.dist > 300 {
            let allowed = total / (Double(m) / 3.6), left = allowed - el
            if left <= 0 {
                hint = "La media ya va a quedar por encima del límite."
            } else {
                let need = dB / left * 3.6
                hint = need >= Double(m)
                    ? "Vas bien: podés seguir hasta \(m) km/h."
                    : "Para terminar en el límite, no pases de \(max(0, Int(need.rounded(.down)))) km/h en lo que queda."
            }
        } else if tr.max == nil {
            hint = "Límite del tramo sin dato: respetá el que marquen las señales."
        }
        if s.over, let m = tr.max, el > 25, t - lastAvgWarn > 45 {
            lastAvgWarn = t
            speak("Velocidad media \(Int(avg.rounded())). Límite \(m).", 2)
        }
        s.minB = min(s.minB, dB)
        if dB < 150 + tr.err { s.nearEnd = true }
        let ended = (s.nearEnd && (dB < 35 || dB > s.minB + 60)) || dB > tr.len * 1.6 + 2000 + tr.err || el > 3 * 3600
        let title = "Tramo · " + tr.name.replacingOccurrences(of: "^Tramo ", with: "", options: .regularExpression)
        var card = TramoInfo(title: title, avg: avg, max: tr.max, progress: min(1, s.dist / max(total, 1)),
                             progressText: "Recorrido \(Fmt.km(s.dist)) · faltan \(Fmt.km(dB))",
                             hint: hint, over: s.over, finished: false)
        if ended {
            speak(s.nearEnd ? "Fin del tramo. Velocidad media \(Int(avg.rounded()))." : "Saliste del tramo.", 1)
            card.hint = s.nearEnd ? "Terminaste con una media de \(Int(avg.rounded())) km/h." : "Saliste del tramo."
            card.finished = true
            card.progress = s.nearEnd ? 1 : card.progress
            tramo = nil
            tAlerted[tr.id] = t
            tramoCard = card
            tramoCardUntil = t + 12
        } else {
            tramo = s
        }
        out.tramo = card
    }
}

// MARK: - simulaciones

struct DemoRoute {
    let path: [LL]
    let kmh: Double
    let message: String
}

enum Demo {
    static func fixed(_ db: RadarDB) -> DemoRoute? {
        let c = db.points.filter { p in
            p.kind == .fixed && p.nearT.isEmpty && p.err == 0 && !(p.aps ?? []).isEmpty && (p.max ?? 0) >= 80
        }
        let pick = c.first { $0.name.range(of: "A-7\\b|A-70|A-31", options: .regularExpression) != nil } ?? c.first
        if let p = pick, let ap = p.aps?.first, ap.pts.count > 1, let m = p.max {
            var path = ap.pts
            let last = path[path.count - 1], prev = path[path.count - 2]
            path.append(Geo.dest(last, Geo.bearing(prev, last), 500))
            let kmh = Double(m + 9)
            return DemoRoute(path: path, kmh: kmh,
                             message: "Simulación: te acercás a \(p.name) a \(Int(kmh)) km/h, siguiendo la carretera.")
        }
        guard let q = db.points.first(where: { $0.kind == .fixed && $0.bear != nil && $0.max != nil }),
              let b = q.bear, let m = q.max else { return nil }
        let s = Geo.dest(q.ll, (b + 180).truncatingRemainder(dividingBy: 360), 1800)
        let e = Geo.dest(q.ll, b, 500)
        return DemoRoute(path: [s, q.ll, e], kmh: Double(m + 9),
                         message: "Simulación: te acercás a \(q.name) a \(m + 9) km/h.")
    }

    static func tramo(_ db: RadarDB) -> DemoRoute? {
        let c = db.tramos.filter { $0.max != nil && $0.len > 1500 && $0.len < 6000 }
            .sorted { a, b in a.exact != b.exact ? a.exact : a.len < b.len }
        guard let tr = c.first(where: { $0.name.range(of: "A-31|A-7|V-31|V-30", options: .regularExpression) != nil }) ?? c.first,
              let m = tr.max else { return nil }
        let p = tr.pts, n = p.count
        let s = Geo.dest(p[0], (Geo.bearing(p[0], p[1]) + 180).truncatingRemainder(dividingBy: 360), 1200)
        let e = Geo.dest(p[n - 1], Geo.bearing(p[n - 2], p[n - 1]), 400)
        return DemoRoute(path: [s] + p + [e], kmh: Double(m + 6),
                         message: "Simulación: recorrés \(tr.name) (\(Fmt.km(tr.len))) a \(m + 6) km/h.")
    }

    static func zone(_ db: RadarDB) -> DemoRoute? {
        guard let z = db.zones.first(where: { $0.exact && $0.len > 2000 && $0.len < 8000 }) else { return nil }
        let p = z.pts
        let s = Geo.dest(p[0], (Geo.bearing(p[0], p[1]) + 180).truncatingRemainder(dividingBy: 360), 600)
        return DemoRoute(path: [s] + p, kmh: 90,
                         message: "Simulación: entrás en un tramo con radares móviles (\(z.road)).")
    }
}

/// Recorre una ruta a velocidad constante, un paso por segundo simulado.
struct SimRunner {
    let path: [LL]
    let v: Double
    private var seg = 0
    private var along = 0.0

    init(path: [LL], v: Double) {
        self.path = path
        self.v = v
    }

    mutating func step() -> (pos: LL, bearing: Double)? {
        guard path.count > 1 else { return nil }
        along += v
        while seg < path.count - 1 {
            let l = Geo.dist(path[seg], path[seg + 1])
            if along <= l { break }
            along -= l
            seg += 1
        }
        if seg >= path.count - 1 { return nil }
        let a = path[seg], b = path[seg + 1]
        let br = Geo.bearing(a, b)
        return (Geo.dest(a, br, along), br)
    }
}
