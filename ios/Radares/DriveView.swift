import SwiftUI

struct DriveView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    GpsPill(state: m.gpsState, text: m.gpsText)
                    Spacer()
                    if m.simulating {
                        Text("SIMULACIÓN")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.purple.opacity(0.25))
                            .foregroundColor(Theme.purple)
                            .clipShape(Capsule())
                    }
                }

                Speedometer(kmh: m.output.kmh, over: m.output.over, active: m.running)

                if let a = m.output.alert { AlertCard(a: a) }
                if let t = m.output.tramo { TramoCard(t: t) }
                if let z = m.output.zone { ZoneCard(z: z) }

                let next = m.running ? m.output.next : "Tocá «Iniciar» antes de salir."
                if !next.isEmpty {
                    Text(next)
                        .font(.subheadline)
                        .foregroundColor(Theme.dim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    if m.running { m.stop() } else { m.start() }
                } label: {
                    Text(m.running ? "Detener" : "Iniciar")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(m.running ? Theme.card : Theme.blue)
                        .foregroundColor(m.running ? Theme.red : .white)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(m.running ? Theme.red : Color.clear, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if !m.note.isEmpty {
                    Text(m.note)
                        .font(.footnote)
                        .foregroundColor(m.noteIsError ? Theme.red : Theme.dim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if !m.dataError.isEmpty {
                    Text(m.dataError)
                        .font(.footnote)
                        .foregroundColor(Theme.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct GpsPill: View {
    let state: GPSState
    let text: String

    var color: Color {
        switch state {
        case .off: return Theme.dim
        case .wait: return Theme.yellow
        case .on: return Theme.green
        case .sim: return Theme.purple
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.footnote.weight(.semibold)).foregroundColor(Theme.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.card)
        .clipShape(Capsule())
    }
}

struct Speedometer: View {
    let kmh: Double
    let over: Bool
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(active ? "\(Int(kmh.rounded()))" : "--")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(over ? Theme.red : Theme.text)
            Text("km/h").font(.headline).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(over ? Theme.red.opacity(0.15) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct AlertCard: View {
    let a: AlertInfo

    var body: some View {
        HStack(spacing: 14) {
            SpeedSign(max: a.max, size: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.kindText.uppercased())
                    .font(.caption.bold())
                    .foregroundColor(a.over ? .white : Theme.red)
                Text(a.label)
                    .font(.headline)
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(distanceText)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Theme.text)
        }
        .padding(14)
        .background(a.over ? Theme.red.opacity(0.85) : Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.red, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var distanceText: String {
        if a.distance < 1000 { return "\(Int((a.distance / 10).rounded()) * 10) m" }
        return String(format: "%.1f", a.distance / 1000).replacingOccurrences(of: ".", with: ",") + " km"
    }
}

struct TramoCard: View {
    let t: TramoInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.title)
                .font(.subheadline.bold())
                .foregroundColor(Theme.orange)
                .lineLimit(2)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Velocidad media").font(.caption).foregroundColor(Theme.dim)
                    Text("\(Int(t.avg.rounded())) km/h")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(t.over ? Theme.red : Theme.text)
                }
                Spacer()
                SpeedSign(max: t.max, size: 60)
            }
            ProgressView(value: t.progress)
                .tint(Theme.orange)
            Text(t.progressText).font(.caption).foregroundColor(Theme.dim)
            if !t.hint.isEmpty {
                Text(t.hint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(t.over ? Theme.red : Theme.text)
            }
        }
        .padding(14)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.over ? Theme.red : Theme.orange, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ZoneCard: View {
    let z: ZoneInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tramo con radares móviles de la DGT")
                    .font(.subheadline.bold())
                    .foregroundColor(Theme.text)
                if !z.label.isEmpty {
                    Text(z.label).font(.caption).foregroundColor(Theme.dim)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.blue.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.blue, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
