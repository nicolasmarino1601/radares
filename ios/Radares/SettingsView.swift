import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Avisos por voz", isOn: $m.settings.voice)
                    Toggle("Tramos con radares móviles de la DGT", isOn: $m.settings.zonas)
                    Toggle("Radares móviles anunciados y zonas habituales", isOn: $m.settings.moviles)
                    Toggle("Posibles radares sin confirmar", isOn: $m.settings.posibles)
                    Toggle("Puntos de radar remolque", isOn: $m.settings.remolque)
                    Toggle("Cámaras de semáforo", isOn: $m.settings.sem)
                    Toggle("Avisar al dejar atrás el radar", isOn: $m.settings.passed)
                    Picker("Distancia del primer aviso", selection: $m.settings.dist) {
                        Text("Automática").tag(0.0)
                        Text("400 m").tag(400.0)
                        Text("700 m").tag(700.0)
                        Text("1 km").tag(1000.0)
                    }
                    Toggle("Pantalla siempre encendida", isOn: $m.settings.keepAwake)
                } header: {
                    Text("Avisos")
                } footer: {
                    Text("«Automática» avisa antes cuanto más rápido vas. «Avisar al dejar atrás el radar» dice «Radar superado» al pasarlo y «Fin del tramo con radares móviles» al salir de uno. Con la pantalla apagada o usando otra app, los avisos siguen sonando.")
                }

                Section {
                    Button("Probar la voz") { m.testVoice() }
                } footer: {
                    Text("Si el iPhone está conectado al auto por Bluetooth o CarPlay, la voz sale por los parlantes del auto y baja un momento la música o el navegador.")
                }

                Section {
                    Picker("Velocidad", selection: $m.settings.simx) {
                        Text("Tiempo real").tag(1.0)
                        Text("x3").tag(3.0)
                        Text("x6").tag(6.0)
                    }
                    Button("Simular un radar fijo") { m.simulate(.fixed) }
                    Button("Simular un tramo de velocidad media") { m.simulate(.tramo) }
                    Button("Simular una zona de radares móviles") { m.simulate(.zone) }
                } header: {
                    Text("Probar sin manejar")
                }

                Section {
                    Text(m.infoText).font(.footnote)
                    Button(m.loading ? "Actualizando…" : "Actualizar radares ahora") { m.loadData(force: true) }
                        .disabled(m.loading)
                } header: {
                    Text("Datos")
                } footer: {
                    Text("Se actualizan solos cada 6 horas cuando hay conexión. Base: Radares Anunciados (ODbL 1.0), que reúne DGT, Servei Català de Trànsit, Gobierno Vasco, Gobierno de Navarra, ayuntamientos de Madrid, Barcelona, Salamanca, Donostia, León y Murcia, y © colaboradores de OpenStreetMap. Se suman los radares del listado oficial de cinemómetros de la DGT que faltaban y cabinas municipales de València.")
                }

                Section {
                    Text("Avisa de radares cuya ubicación es pública. No detecta ni interfiere radares. Respetá siempre los límites y las señales.")
                        .font(.footnote)
                        .foregroundColor(Theme.dim)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
