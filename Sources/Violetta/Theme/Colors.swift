import SwiftUI

extension Color {
    /// Backgrounds
    static let violetBackground = Color(hex: 0x0F0F0F)
    static let violetBackgroundElevated = Color(hex: 0x1A1A1A)
    static let violetSurface = Color(hex: 0x1E1E1E)
    
    /// Primary
    static let violetPrimary = Color(hex: 0x7C5CBF)
    static let violetPrimaryHover = Color(hex: 0x9370DB)
    static let violetDanger = Color(hex: 0xE74C3C)
    
    /// Tag System
    struct Tag {
        static let female = Color(hex: 0xC48DA0)
        static let male = Color(hex: 0x7DA1C4)
        static let artist = Color(hex: 0xC4A84E)
        static let series = Color(hex: 0x6BB89E)
        static let group = Color(hex: 0x9B8ABF)
        static let character = Color(hex: 0xC49070)
        static let generic = Color(hex: 0x8A8F96)
    }
    
    static func themeColor(for name: String) -> Color {
        let dynamicColor = UIColor { traitCollection in
            let isDark = traitCollection.userInterfaceStyle == .dark
            switch name {
            case "black": return isDark ? UIColor(hex: 0xf3f4f6) : UIColor(hex: 0x1f2937)
            case "grey": return isDark ? UIColor(hex: 0x9ca3af) : UIColor(hex: 0x4b5563)
            case "yellow": return isDark ? UIColor(hex: 0xfde047) : UIColor(hex: 0xca8a04)
            case "lime": return isDark ? UIColor(hex: 0xa3e635) : UIColor(hex: 0x65a30d)
            case "purple": return isDark ? UIColor(hex: 0xa78bfa) : UIColor(hex: 0x7c3aed)
            case "blueGrey": return isDark ? UIColor(hex: 0x94a3b8) : UIColor(hex: 0x475569)
            // Default palette fallback
            default:
                let colors: [String: UInt] = [
                    "amber": 0xf59e0b, "blue": 0x3b82f6, "brown": 0xa16207,
                    "cyan": 0x06b6d4, "deepOrange": 0xea580c, "deepPurple": 0x7c3aed,
                    "green": 0x10b981, "indigo": 0x6366f1,
                    "lightBlue": 0x0ea5e9, "lightGreen": 0x84cc16,
                    "orange": 0xf97316, "pink": 0xec4899, "red": 0xef4444,
                    "teal": 0x14b8a6
                ]
                return UIColor(hex: colors[name] ?? 0x7c3aed)
            }
        }
        return Color(uiColor: dynamicColor)
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}
