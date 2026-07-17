import Foundation

enum SavePetPreset: String, Codable, CaseIterable, Identifiable {
    case sprout
    case spark
    case cloud

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .sprout: return "leaf.fill"
        case .spark: return "sparkles"
        case .cloud: return "cloud.fill"
        }
    }
}

enum SavePetStage: String, Codable, CaseIterable {
    case hatchling
    case companion
    case guardian

    init(xp: Int) {
        if xp >= 60 {
            self = .guardian
        } else if xp >= 20 {
            self = .companion
        } else {
            self = .hatchling
        }
    }

    var nextThreshold: Int? {
        switch self {
        case .hatchling: return 20
        case .companion: return 60
        case .guardian: return nil
        }
    }

    func progress(xp: Int) -> Double {
        switch self {
        case .hatchling:
            return min(max(Double(xp) / 20, 0), 1)
        case .companion:
            return min(max(Double(xp - 20) / 40, 0), 1)
        case .guardian:
            return 1
        }
    }
}
