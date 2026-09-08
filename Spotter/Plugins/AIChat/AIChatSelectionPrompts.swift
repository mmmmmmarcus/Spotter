import Foundation

/// The prompts the two shipped AI commands start life with. A prompt is a template: `{selection}` is
/// where the selected text lands, and a prompt without the token gets it appended instead.
enum AIChatSelectionPrompts {
    static let defaultDefinition =
        "Act as a bilingual dictionary and language tutor. Define and explain the word or phrase "
        + "below in both English and Simplified Chinese. Start with ‘English:’ and then ‘中文：’, "
        + "include the part of speech when relevant, and keep both explanations concise. Answer any "
        + "follow-up questions about the term.\n\n{selection}"
    static let defaultGrammar =
        "Proofread the text below without changing its meaning, tone, language or formatting. Show "
        + "the complete corrected text first, then briefly explain each change; say that no issues "
        + "were found when it is already correct. Revise further if asked.\n\n{selection}"
}
