import SwiftUI

struct ListScreen: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @State private var rows: [Row] = []
    @State private var info = ""

    struct Row: Identifiable {
        let id: String
        let type: String
        let color: Color
        let label: String
        let max: Int?
        let ll: LL
        var d: Double?
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { r in
                        Button {
                            m.mapFocus = r.ll
                            m.tab = .map
                        } label: {
                            RowView(r: r)
                        }
                        .listRowBackground(Theme.bg)
                    }
                } footer: {
                    Text(info).font(.caption).foregroundColor(Theme.dim)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $query, prompt: "Carretera, ciudad o tipo")
            .navigationTitle("Radares")
            .onAppear(perform: rebuild)
            .onChange(of: query) { _ in rebuild() }
            .onChange(of: m.dbVersion) { _ in rebuild() }
            .onChange(of: m.settings) { _ in rebuild() }
        }
    }

    private func rebuild() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var all: [Row] = []
        for p in m.db.points where m.settings.shows(p) {
            all.append(Row(id: "p" + p.id, type: p.err > 0 ? "Radar fijo · ubicación aproximada" : p.kind.label,
                           color: Color(hex: Theme.hex(for: p)), label: p.name, max: p.max, ll: p.ll))
        }
        for t in m.db.tramos {
            all.append(Row(id: "t" + t.id, type: "Tramo de velocidad media · " + Fmt.km(t.len), color: Theme.orange,
                           label: t.name, max: t.max, ll: t.a))
        }
        if m.settings.zonas {
            for z in m.db.zones {
                var label = z.road
                if let a = z.kmFrom { label += " km \(Fmt.num(a))–\(Fmt.num(z.kmTo ?? a))" }
                all.append(Row(id: "z" + z.id, type: "Tramo con radares móviles", color: Theme.blue, label: label,
                               max: nil, ll: z.a))
            }
        }
        var list = q.isEmpty ? all : all.filter { $0.label.lowercased().contains(q) || $0.type.lowercased().contains(q) }
        if let me = m.me {
            for i in list.indices { list[i].d = Geo.dist(me, list[i].ll) }
            list.sort { ($0.d ?? 0) < ($1.d ?? 0) }
        } else {
            list.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "es_ES")
        nf.numberStyle = .decimal
        let total = nf.string(from: NSNumber(value: list.count)) ?? String(list.count)
        info = "\(total) puntos" + (m.me != nil ? " · ordenados por distancia" : " · ordenados por nombre")
            + (list.count > 300 ? " · se muestran 300" : "")
        rows = Array(list.prefix(300))
    }
}

private struct RowView: View {
    let r: ListScreen.Row

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(r.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline).foregroundColor(Theme.text).lineLimit(2)
                Text(r.type).font(.caption).foregroundColor(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(r.max.map { "\($0)" } ?? "–").font(.subheadline.bold()).foregroundColor(Theme.text)
                Text(r.d.map { Fmt.km($0) } ?? "km/h").font(.caption).foregroundColor(Theme.dim)
            }
        }
        .padding(.vertical, 2)
    }
}
