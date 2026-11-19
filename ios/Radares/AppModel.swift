import SwiftUI
import CoreLocation
import UIKit

enum GPSState {
    case off, wait, on, sim
}

enum AppTab: Hashable {
    case drive, map, list, settings
}

enum DemoKind {
    case fixed, tramo, zone
}

/// Estado de la app. Todo se usa desde el hilo principal.
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            engine.settings = settings
            speaker.enabled = settings.voice
            updateIdleTimer()
        }
    }
    @Published private(set) var output = EngineOutput()
    @Published private(set) var running = false
    @Published private(set) var simulating = false
    @Published private(set) var gpsState: GPSState = .off
    @Published private(set) var gpsText = "GPS apagado"
    @Published private(set) var note = ""
    @Published private(set) var noteIsError = false
    @Published private(set) var loading = false
    @Published private(set) var dataError = ""
    @Published private(set) var infoText = "Cargando radares…"
    @Published private(set) var db = RadarDB()
    @Published private(set) var dbVersion = 0
    @Published var tab: AppTab = .drive
    @Published var mapFocus: LL? = nil
    private(set) var me: LL?

    let speaker = Speaker()
    private let location = LocationService()
    private let store = DataStore()
    private var engine: Engine!
    private var simTimer: Timer?
    private var sim: SimRunner?
    private var simT: Double = 0
    private var simKmh: Double = 0
    private var dataOrigin = ""
    private var dataDate: Date?
    private static let settingsKey = "radares-ajustes"

    init() {
        var s = Settings()
        if let d = UserDefaults.standard.data(forKey: AppModel.settingsKey),
           let saved = try? JSONDecoder().decode(Settings.self, from: d) {
            s = saved
        }
        settings = s
        speaker.enabled = s.voice
        engine = Engine(db: db, settings: s, speak: { [weak self] text, beeps in
            self?.speaker.say(text, beeps: beeps)
        })
        location.onLocation = { [weak self] loc in self?.handle(loc) }
        location.onError = { [weak self] msg in self?.gpsFailed(msg) }
        loadData(force: false)
    }

    private func saveSettings() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: AppModel.settingsKey) }
    }

    // MARK: datos

    func loadData(force: Bool) {
        guard !loading else { return }
        loading = true
        if force || db.points.isEmpty { infoText = "Cargando radares…" }
        store.load(force: force) { [weak self] loaded in
            guard let self = self else { return }
            let supp = Bundle.main.url(forResource: "supp", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            DispatchQueue.global(qos: .userInitiated).async {
                func obj(_ d: Data?) -> [String: Any]? {
                    guard let d = d else { return nil }
                    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                }
                let newDB = RadarDB.build(feed: obj(loaded.feed), roads: obj(loaded.roads), supp: obj(supp),
                                          today: RadarDB.todayISO())
                DispatchQueue.main.async {
                    self.db = newDB
                    self.engine.db = newDB
                    self.dbVersion += 1
                    self.dataOrigin = loaded.origin
                    self.dataDate = loaded.date
                    self.dataError = loaded.error ?? ""
                    self.loading = false
                    self.infoText = self.describeData()
                }
            }
        }
    }

    private func describeData() -> String {
        let c = db.counts
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "es_ES")
        nf.numberStyle = .decimal
        func n(_ x: Int) -> String { nf.string(from: NSNumber(value: x)) ?? String(x) }
        var s = "\(n(c.fixed)) radares fijos · \(n(c.tramos)) tramos de velocidad media · \(n(c.zones)) tramos con radares móviles de la DGT · \(n(c.mobile)) radares móviles anunciados o frecuentes · \(n(c.trailer)) puntos de radar remolque · \(n(c.possible)) posibles radares sin confirmar · \(n(c.redLight)) cámaras de semáforo."
        if c.pdfFixed > 0 || c.pdfTramos > 0 {
            s += "\nIncluye \(c.pdfFixed) radares fijos y \(c.pdfTramos) tramos del listado oficial de la DGT (\(db.suppDate)) que todavía no estaban en el mapa, ubicados por su punto kilométrico (posición aproximada)."
        }
        var when = ""
        if let d = dataDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateStyle = .short
            f.timeStyle = .short
            when = " · " + f.string(from: d)
        }
        s += "\nDatos \(dataOrigin)\(when)."
        return s
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            if !running && store.isStale { loadData(force: false) }
            updateIdleTimer()
        }
    }

    // MARK: GPS

    func start() {
        stopSimulation()
        engine.reset()
        output = EngineOutput()
        running = true
        gpsState = .wait
        gpsText = "Buscando GPS…"
        setNote("Podés bloquear el teléfono o abrir otra app (Google Maps, música): los avisos siguen sonando.")
        speaker.prepare()
        location.start()
        updateIdleTimer()
    }

    func stop() {
        location.stop()
        stopSimulation()
        running = false
        engine.reset()
        output = EngineOutput()
        gpsState = .off
        gpsText = "GPS apagado"
        setNote("")
        updateIdleTimer()
    }

    private func handle(_ loc: CLLocation) {
        guard running, !simulating else { return }
        guard loc.horizontalAccuracy >= 0 else { return }
        gpsState = .on
        gpsText = "GPS ±\(Int(loc.horizontalAccuracy.rounded())) m"
        fix(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
            speed: loc.speed >= 0 ? loc.speed : nil,
            heading: loc.course >= 0 ? loc.course : nil,
            accuracy: loc.horizontalAccuracy,
            t: loc.timestamp.timeIntervalSince1970)
    }

    private func fix(lat: Double, lon: Double, speed: Double?, heading: Double?, accuracy: Double?, t: Double) {
        let o = engine.onFix(lat: lat, lon: lon, speed: speed, heading: heading, accuracy: accuracy, t: t)
        me = LL(lat, lon)
        if o != output { output = o }
    }

    private func gpsFailed(_ msg: String) {
        location.stop()
        running = false
        gpsState = .off
        gpsText = "Sin GPS"
        setNote(msg, error: true)
        updateIdleTimer()
    }

    private func setNote(_ text: String, error: Bool = false) {
        note = text
        noteIsError = error
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = running && settings.keepAwake
    }

    // MARK: simulación

    func simulate(_ kind: DemoKind) {
        let route: DemoRoute?
        switch kind {
        case .fixed: route = Demo.fixed(db)
        case .tramo: route = Demo.tramo(db)
        case .zone: route = Demo.zone(db)
        }
        guard let r = route else {
            setNote("Todavía no hay radares cargados para simular.", error: true)
            return
        }
        location.stop()
        stopSimulation()
        engine.reset()
        output = EngineOutput()
        running = true
        simulating = true
        gpsState = .sim
        gpsText = "Simulación"
        setNote(r.message)
        tab = .drive
        speaker.prepare()
        sim = SimRunner(path: r.path, v: r.kmh / 3.6)
        simKmh = r.kmh
        simT = Date().timeIntervalSince1970
        simStep()
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / max(1, settings.simx), repeats: true) { [weak self] _ in
            self?.simStep()
        }
        updateIdleTimer()
    }

    private func simStep() {
        guard var s = sim else { return }
        guard let step = s.step() else {
            stopSimulation()
            running = false
            gpsState = .off
            gpsText = "GPS apagado"
            setNote("Fin de la simulación.")
            updateIdleTimer()
            return
        }
        sim = s
        simT += 1
        let noise = Double.random(in: -2...2) / 3.6
        fix(lat: step.pos.lat, lon: step.pos.lon, speed: simKmh / 3.6 + noise, heading: step.bearing, accuracy: 5, t: simT)
    }

    private func stopSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        sim = nil
        simulating = false
    }

    func testVoice() {
        speaker.say("Radar fijo a 500 metros. Límite 100.", beeps: 1)
    }
}
