import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(hex: 0x0B0F14)
    static let card = Color(hex: 0x151B23)
    static let line = Color(hex: 0x243041)
    static let text = Color(hex: 0xE8EEF5)
    static let dim = Color(hex: 0x8A97A8)
    static let red = Color(hex: 0xFF4D4F)
    static let orange = Color(hex: 0xFF8A3D)
    static let blue = Color(hex: 0x3AA0FF)
    static let pink = Color(hex: 0xFF5EC4)
    static let yellow = Color(hex: 0xFFD23F)
    static let purple = Color(hex: 0xB07CFF)
    static let green = Color(hex: 0x3DDC84)

    static func hex(for p: RadarPoint) -> UInt32 {
        if p.err > 0 { return 0xFF9A9A }
        switch p.kind {
        case .fixed: return 0xFF4D4F
        case .trailer: return 0xFFB020
        case .mobileAnnounced, .mobileRecurring: return 0xFF5EC4
        case .possible: return 0xB07CFF
        case .redLight: return 0xFFD23F
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Señal de límite de velocidad.
struct SpeedSign: View {
    let max: Int?
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(Theme.red, lineWidth: size * 0.12)
            Text(max.map { "\($0)" } ?? "?")
                .font(.system(size: size * (max ?? 0 >= 100 ? 0.34 : 0.4), weight: .heavy, design: .rounded))
                .foregroundColor(max == nil ? .gray : .black)
        }
        .frame(width: size, height: size)
    }
}
