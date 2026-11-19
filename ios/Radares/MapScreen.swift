import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            RadarMapView(db: m.db, version: m.dbVersion, settings: m.settings, focus: $m.mapFocus)
                .ignoresSafeArea(edges: .top)
            Text("Acercá el mapa para ver cada radar. Tocá un punto para ver el detalle.")
                .font(.caption)
                .foregroundColor(Theme.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.bg.opacity(0.8))
                .clipShape(Capsule())
                .padding(.bottom, 8)
        }
    }
}

final class RadarAnnotation: NSObject, MKAnnotation {
    let point: RadarPoint

    init(_ p: RadarPoint) {
        point = p
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon) }
    var title: String? { point.err > 0 ? "Radar fijo (ubicación aproximada)" : point.kind.label }
    var subtitle: String? {
        let lim = point.max.map { "\($0) km/h" } ?? "sin dato"
        var s = "\(point.name) · límite \(lim)"
        if point.err > 0 { s += " · margen ±\(Fmt.km(point.err))" }
        return s
    }
}

struct RadarMapView: UIViewRepresentable {
    let db: RadarDB
    let version: Int
    let settings: Settings
    @Binding var focus: LL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.pointOfInterestFilter = .excludingAll
        mv.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.2, longitude: -3.7),
                                        span: MKCoordinateSpan(latitudeDelta: 9, longitudeDelta: 11)), animated: false)
        let button = MKUserTrackingButton(mapView: mv)
        button.backgroundColor = UIColor(hex: 0x151B23, alpha: 0.9)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        mv.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: mv.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: mv.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        context.coordinator.mapView = mv
        return mv
    }

    func updateUIView(_ mv: MKMapView, context: Context) {
        let c = context.coordinator
        c.db = db
        if c.version != version || c.settings != settings {
            c.version = version
            c.settings = settings
            c.reloadOverlays()
            c.refreshAnnotations()
        }
        if let f = focus {
            mv.userTrackingMode = .none
            mv.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon),
                                            latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
            DispatchQueue.main.async { focus = nil }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var db = RadarDB()
        var version = -1
        var settings = Settings()
        private var shown: [String: RadarAnnotation] = [:]
        private var images: [String: UIImage] = [:]

        private func polyline(_ pts: [LL]) -> MKPolyline {
            let coords = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            return MKPolyline(coordinates: coords, count: coords.count)
        }

        func reloadOverlays() {
            guard let mv = mapView else { return }
            mv.removeOverlays(mv.overlays)
            func add(_ lines: [MKPolyline], _ tag: String) {
                guard !lines.isEmpty else { return }
                let mp = MKMultiPolyline(lines)
                mp.title = tag
                mv.addOverlay(mp)
            }
            if settings.zonas { add(db.zones.map { polyline($0.pts) }, "zone") }
            add(db.tramos.filter { $0.err == 0 }.map { polyline($0.pts) }, "tramo")
            add(db.tramos.filter { $0.err > 0 }.map { polyline($0.pts) }, "tramoApprox")
        }

        func refreshAnnotations() {
            guard let mv = mapView else { return }
            let r = mv.region
            var want: [String: RadarPoint] = [:]
            if r.span.latitudeDelta < 1.0 {
                let la0 = r.center.latitude - r.span.latitudeDelta / 2, la1 = r.center.latitude + r.span.latitudeDelta / 2
                let lo0 = r.center.longitude - r.span.longitudeDelta / 2, lo1 = r.center.longitude + r.span.longitudeDelta / 2
                for p in db.points where settings.shows(p) {
                    if p.lat >= la0 && p.lat <= la1 && p.lon >= lo0 && p.lon <= lo1 {
                        want[p.id] = p
                        if want.count >= 900 { break }
                    }
                }
            }
            var remove: [RadarAnnotation] = []
            for (id, a) in shown where want[id] == nil || want[id]! !== a.point {
                remove.append(a)
                shown[id] = nil
            }
            if !remove.isEmpty { mv.removeAnnotations(remove) }
            var add: [RadarAnnotation] = []
            for (id, p) in want where shown[id] == nil {
                let a = RadarAnnotation(p)
                shown[id] = a
                add.append(a)
            }
            if !add.isEmpty { mv.addAnnotations(add) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshAnnotations()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let mp = overlay as? MKMultiPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKMultiPolylineRenderer(multiPolyline: mp)
            switch mp.title ?? "" {
            case "zone":
                r.strokeColor = UIColor(hex: 0x3AA0FF, alpha: 0.6)
                r.lineWidth = 4
            case "tramoApprox":
                r.strokeColor = UIColor(hex: 0xFF8A3D, alpha: 0.9)
                r.lineWidth = 5
                r.lineDashPattern = [6, 6]
            default:
                r.strokeColor = UIColor(hex: 0xFF8A3D, alpha: 0.95)
                r.lineWidth = 5
            }
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? RadarAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "radar")
                ?? MKAnnotationView(annotation: a, reuseIdentifier: "radar")
            v.annotation = a
            v.canShowCallout = true
            v.image = dot(Theme.hex(for: a.point), size: a.point.kind == .fixed ? 14 : 12)
            return v
        }

        private func dot(_ hex: UInt32, size: CGFloat) -> UIImage {
            let key = "\(hex)-\(size)"
            if let img = images[key] { return img }
            let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
                UIColor(hex: hex).setFill()
                ctx.cgContext.fillEllipse(in: rect)
                UIColor(hex: 0x0B0F14).setStroke()
                ctx.cgContext.setLineWidth(1.5)
                ctx.cgContext.strokeEllipse(in: rect)
            }
            images[key] = img
            return img
        }
    }
}
