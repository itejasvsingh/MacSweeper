import Foundation
import SwiftUI

enum SafetyTier: String, CaseIterable {
    case safe = "Safe"
    case review = "Review"
    case caution = "Caution"

    var color: Color {
        switch self {
        case .safe: return .green
        case .review: return .orange
        case .caution: return .red
        }
    }
}

enum TargetCategory: String, CaseIterable {
    case aiAndVMs = "AI & VMs"
    case developer = "Developer"
    case messaging = "Messaging"
    case system = "System & Caches"
}

struct CleanupTarget: Identifiable {
    let id = UUID()
    let name: String
    let category: TargetCategory
    let safety: SafetyTier
    let explanation: String
    let paths: [URL]
    var sizeBytes: Int64 = 0
    var exists: Bool = false
    var isSelected: Bool = false
}

struct RelatedFile: Identifiable {
    let id = UUID()
    let url: URL
    let location: String
    let size: Int64
    var isSelected: Bool = true
    var isSystemWide: Bool = false
}

struct InstalledApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String
    let appURL: URL
    let appSize: Int64
    var relatedFiles: [RelatedFile]
    var isRunning: Bool

    var totalSize: Int64 {
        appSize + relatedFiles.reduce(0) { $0 + $1.size }
    }

    var selectedTotalSize: Int64 {
        appSize + relatedFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
}

struct OrphanFolder: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let location: String
    let size: Int64
    var isSelected: Bool = false
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
