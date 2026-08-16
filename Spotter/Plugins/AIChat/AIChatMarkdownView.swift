import SwiftUI

/// Renders one assistant reply's Markdown: `AIChatMarkdown` splits the blocks, SwiftUI's own parser
/// handles the inline spans inside each one.
struct AIChatMarkdownText: View {
    let text: String

    private var blocks: [AIChatMarkdownBlock] { AIChatMarkdown.blocks(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AIChatMarkdownBlock {
    @ViewBuilder
    fileprivate var view: some View {
        switch self {
        case .paragraph(let text):
            AIChatInlineText(text: text)
        case .heading(let level, let text):
            AIChatInlineText(text: text)
                .font(headingFont(level))
        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Text(marker)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                AIChatInlineText(text: text)
            }
            .padding(.leading, CGFloat(depth) * Theme.Spacing.xl)
        case .quote(let text):
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.Colors.border)
                    .frame(width: 2)
                AIChatInlineText(text: text)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(_, let text):
            Text(text)
                .font(Theme.Typography.chatCode)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
        case .table(let header, let rows):
            AIChatMarkdownTable(header: header, rows: rows)
        case .rule:
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: Theme.Typography.chatHeading
        case 2: Theme.Typography.chatSubheading
        default: Theme.Typography.chatMinorHeading
        }
    }
}

/// A single run of inline Markdown — bold, italics, code spans, strikethrough and links.
private struct AIChatInlineText: View {
    let text: String

    var body: some View {
        Text(Self.attributed(text))
            .font(Theme.Typography.rowTitle)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whitespace is preserved so a hard-wrapped paragraph keeps its own line breaks; a reply that
    /// fails to parse renders as the plain text the model sent rather than disappearing.
    static func attributed(_ text: String) -> AttributedString {
        guard
            var attributed = try? AttributedString(
                markdown: text,
                options: .init(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible))
        else { return AttributedString(text) }
        let codeRuns = attributed.runs.filter {
            $0.inlinePresentationIntent?.contains(.code) == true
        }.map(\.range)
        for range in codeRuns {
            attributed[range].font = Theme.Typography.chatInlineCode
        }
        return attributed
    }
}

private struct AIChatMarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xl, verticalSpacing: Theme.Spacing.sm) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    cellText(cell)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
                .gridCellUnsizedAxes(.horizontal)
                .gridCellColumns(max(header.count, 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    // Padded to the header width so a short row cannot shift its columns left.
                    ForEach(0..<header.count, id: \.self) { column in
                        cellText(column < row.count ? row[column] : "")
                    }
                }
            }
        }
    }

    private func cellText(_ text: String) -> some View {
        Text(AIChatInlineText.attributed(text))
            .font(Theme.Typography.rowTitle)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
