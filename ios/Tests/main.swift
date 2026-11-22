// Prueba del motor de avisos con los datos reales.
// Uso: enginetest feed.geojson roads.json supp.json
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  OK   \(what)" : "  FALLA \(what)")
    if !ok { failures += 1 }
}

func load(_ path: String) -> [String: Any]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

// --- utilidades ---
print("Utilidades")
let ref = Geo.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
check(ref.count == 3 && abs(ref[0].lat - 38.5) < 1e-9 && abs(ref[0].lon + 120.2) < 1e-9
      && abs(ref[2].lat - 43.252) < 1e-9 && abs(ref[2].lon + 126.453) < 1e-9, "polilínea de referencia de Google")
check(Fmt.say(430) == "450 metros" && Fmt.say(1000) == "1 kilómetro" && Fmt.say(1240) == "1,2 kilómetros", "distancias habladas")
check(Fmt.km(345) == "350 m" && Fmt.km(2500) == "2,5 km", "distancias escritas")
check(abs(Geo.dist(40, -3, 40.01, -3) - 1111.95) < 1, "distancia")
check(abs(Geo.bearing(40, -3, 40, -2.9) - 90) < 0.1, "rumbo")

// --- datos ---
let args = CommandLine.arguments
guard args.count >= 4 else { print("faltan argumentos"); exit(2) }
let t0 = Date()
let db = RadarDB.build(feed: load(args[1]), roads: load(args[2]), supp: load(args[3]), today: RadarDB.todayISO())
print("\nDatos (\(String(format: "%.2f", Date().timeIntervalSince(t0))) s): \(db.counts)")
check(db.counts.fixed > 1500, "más de 1.500 radares fijos")
check(db.counts.tramos > 150, "más de 150 tramos")
check(db.counts.zones > 800, "más de 800 tramos de radares móviles")
check(db.points.contains { $0.aps != nil }, "radares con aproximación por carretera")
check(db.tramos.contains { $0.exact }, "tramos con trazado exacto")

final class Box { var said: [String] = [] }

func drive(_ route: DemoRoute?, _ name: String, settings: Settings = Settings(), reverse: Bool = false) -> [String] {
    guard let r = route else {
        check(false, "\(name): hay ruta para simular")
        return []
    }
    let box = Box()
    let eng = Engine(db: db, settings: settings, speak: { txt, _ in box.said.append(txt) })
    var sim = SimRunner(path: reverse ? Array(r.path.reversed()) : r.path, v: r.kmh / 3.6)
    var t = 1000.0
    var fixes = 0
    let start = Date()
    while let s = sim.step() {
        t += 1
        fixes += 1
        eng.onFix(lat: s.pos.lat, lon: s.pos.lon, speed: r.kmh / 3.6, heading: s.bearing, accuracy: 5, t: t)
    }
    let ms = Date().timeIntervalSince(start) * 1000 / Double(max(fixes, 1))
    print("\n\(name)\(reverse ? " (al revés)" : ""): \(r.message)")
    print("  \(fixes) posiciones, \(String(format: "%.2f", ms)) ms por posición")
    for s in box.said { print("  voz: \(s)") }
    return box.said
}

let f = drive(Demo.fixed(db), "Radar fijo")
check(f.contains { $0.hasPrefix("Radar fijo a") }, "avisa el radar fijo")
check(f.contains { $0.hasPrefix("Atención. Vas a") }, "avisa que vas pasado")

let tr = drive(Demo.tramo(db), "Tramo")
check(tr.contains { $0.hasPrefix("Tramo de velocidad media a") }, "preaviso del tramo")
check(tr.contains { $0.hasPrefix("Empieza el tramo") }, "inicio del tramo")
check(tr.contains { $0.hasPrefix("Fin del tramo") }, "fin del tramo")

let z = drive(Demo.zone(db), "Zona de radares móviles")
check(z.contains { $0.hasPrefix("Tramo con radares móviles") }, "aviso de zona de móviles")

var noZones = Settings()
noZones.zonas = false
let z2 = drive(Demo.zone(db), "Zona con el aviso apagado", settings: noZones)
check(!z2.contains { $0.hasPrefix("Tramo con radares móviles") }, "respeta el ajuste de zonas")

// En sentido contrario, el radar fijo de la simulación (que vigila un solo sentido) no debe avisar
// a menos de 100 m de su posición.
if let r = Demo.fixed(db) {
    let back = drive(r, "Radar fijo", reverse: true)
    print("  (avisos en sentido contrario: \(back.count))")
}

print(failures == 0 ? "\nTodo bien." : "\n\(failures) fallas.")
exit(failures == 0 ? 0 : 1)
