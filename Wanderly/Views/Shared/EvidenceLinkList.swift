import SwiftUI

struct EvidenceLinkList: View {
    var evidence: [String]
    var maxItems: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(displayedEvidence.enumerated()), id: \.offset) { _, item in
                EvidenceLinkRow(text: item)
            }
        }
    }

    private var displayedEvidence: [String] {
        Array(evidence.prefix(maxItems))
    }
}

private struct EvidenceLinkRow: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !links.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(links) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: link.systemImage)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.saveCocoa.opacity(0.1))
                                .foregroundColor(.saveCocoa)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("source url:") {
            return "Source"
        }
        return trimmed
    }

    private var links: [EvidenceLink] {
        EvidenceLink.extract(from: text)
    }
}

private struct EvidenceLink: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let systemImage: String

    static func extract(from text: String) -> [EvidenceLink] {
        var links: [EvidenceLink] = []
        var seen = Set<String>()

        for url in urls(in: text) {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            links.append(EvidenceLink(
                id: key,
                title: linkTitle(for: url),
                url: url,
                systemImage: "link"
            ))
        }

        for handle in instagramHandles(in: text) {
            guard let url = URL(string: "https://www.instagram.com/\(handle)/") else { continue }
            let key = "instagram:\(handle.lowercased())"
            guard seen.insert(key).inserted else { continue }
            links.append(EvidenceLink(
                id: key,
                title: "@\(handle)",
                url: url,
                systemImage: "camera"
            ))
        }

        return links
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }

    private static func instagramHandles(in text: String) -> [String] {
        let pattern = #"(?<![A-Za-z0-9._])@([A-Za-z0-9._]{2,30})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            let handle = String(text[captureRange]).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
            guard !handle.isEmpty, !handle.contains("..") else { return nil }
            return handle
        }
    }

    private static func linkTitle(for url: URL) -> String {
        guard let host = url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") else {
            return "Open link"
        }
        if host.hasSuffix("instagram.com") {
            return "Open Instagram"
        }
        if host.hasSuffix("maps.app.goo.gl") || host.hasSuffix("google.com") {
            return "Open map"
        }
        return host
    }
}
