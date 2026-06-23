import Foundation

enum TrackingMode: String, CaseIterable, Identifiable {
    case blur
    case pixelate

    var id: String { rawValue }
}

enum VirtualBackgroundMode: String, CaseIterable, Identifiable {
    case none
    case blur
    case solidColor
    case image

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Sin fondo"
        case .blur:
            return "Fondo turbio"
        case .solidColor:
            return "Color plano"
        case .image:
            return "Imagen"
        }
    }
}

enum VirtualBackgroundColorPreset: String, CaseIterable, Identifiable {
    case dark
    case blue
    case green
    case purple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark:
            return "Oscuro"
        case .blue:
            return "Azul"
        case .green:
            return "Verde"
        case .purple:
            return "Morado"
        }
    }
}
