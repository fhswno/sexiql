import Foundation

struct SettingsSearchItem: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
    let section: SettingsSection

    init(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String],
        section: SettingsSection
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.section = section
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if title.lowercased().contains(q) { return true }
        if subtitle.lowercased().contains(q) { return true }
        return keywords.contains { keyword in
            let k = keyword.lowercased()
            return k.contains(q) || q.contains(k)
        }
    }
}
