import Foundation

/// One selectable model, already stripped of the brand prefix its catalog name carries.
struct OpenRouterModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// The models one vendor publishes, newest first.
struct OpenRouterModelBrand: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let models: [OpenRouterModel]
}

/// Turns OpenRouter's `/models` payload into the two-level brand → model menu.
/// Foundation-only and pure — `Tools/ai-chat-test.swift` compiles it standalone; the fetch lives in
/// `OpenRouterStore`.
enum OpenRouterModelCatalog {
    static func brands(fromJSON data: Data) throws -> [OpenRouterModelBrand] {
        brands(from: try JSONDecoder().decode(Payload.self, from: data).data)
    }

    static func brands(from entries: [Entry]) -> [OpenRouterModelBrand] {
        var grouped: [String: [Ranked]] = [:]
        var titles: [String: String] = [:]
        var seen: Set<String> = []

        for entry in entries {
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted, entry.answersInText else { continue }
            let slug = Self.slug(of: id)
            let split = Self.split(name: entry.name)
            titles[slug] = titles[slug] ?? split.brand ?? Self.prettified(slug)
            let label = split.model ?? Self.tail(of: id)
            grouped[slug, default: []].append(
                Ranked(model: OpenRouterModel(id: id, name: label), created: entry.created ?? 0))
        }

        return grouped.map { slug, ranked in
            OpenRouterModelBrand(
                id: slug,
                title: titles[slug] ?? Self.prettified(slug),
                // Newest first, so "the latest model" is the first thing the submenu offers.
                models: ranked.sorted {
                    $0.created == $1.created
                        ? $0.model.name.localizedCaseInsensitiveCompare($1.model.name)
                            == .orderedAscending
                        : $0.created > $1.created
                }.map(\.model))
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The catalog label for a stored id, or nil when this catalog doesn't carry it.
    static func label(for id: String, in brands: [OpenRouterModelBrand]) -> String? {
        for brand in brands {
            if let model = brand.models.first(where: { $0.id == id }) {
                return "\(brand.title) · \(model.name)"
            }
        }
        return nil
    }

    struct Entry: Decodable {
        let id: String
        let name: String?
        let created: Double?
        let architecture: Architecture?

        struct Architecture: Decodable {
            let output_modalities: [String]?
        }

        /// Image and audio generators share the endpoint but can never answer a chat turn.
        var answersInText: Bool {
            guard let modalities = architecture?.output_modalities else { return true }
            return modalities.contains("text")
        }
    }

    private struct Payload: Decodable {
        let data: [Entry]
    }

    private struct Ranked {
        let model: OpenRouterModel
        let created: Double
    }

    private static func slug(of id: String) -> String {
        guard let slash = id.firstIndex(of: "/") else { return id }
        return String(id[id.startIndex..<slash])
    }

    private static func tail(of id: String) -> String {
        guard let slash = id.firstIndex(of: "/") else { return id }
        return String(id[id.index(after: slash)...])
    }

    /// Catalog names read "Anthropic: Claude Sonnet 5"; the brand is already the group header.
    private static func split(name: String?) -> (brand: String?, model: String?) {
        guard let name, let colon = name.firstIndex(of: ":") else { return (nil, nil) }
        let brand = String(name[name.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let model = String(name[name.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !brand.isEmpty, !model.isEmpty else { return (nil, nil) }
        return (brand, model)
    }

    private static func prettified(_ slug: String) -> String {
        let words = slug.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard !words.isEmpty else { return slug }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
