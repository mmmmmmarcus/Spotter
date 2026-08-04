# Change Case plugin

Change Case implements the 21 transformations exposed by the Raycast extension: camel, capital,
constant, dot, header, lower, lower-first, no-case, kebab, upper-kebab, Pascal, Pascal-snake, path,
random, sentence, snake, alternating, swap, title, upper and upper-first.

The preferred input can be selected text or the clipboard; an empty preferred source falls back to
the other. Reading selection goes through the shared stateless `SelectedTextReader` (its synchronous
single-shot path), while pasting uses Accessibility only after the user invokes an action. Change
Case keeps its explicit clipboard-source fallback; Selection Tools instead layers a guarded ⌘C
fallback behind Accessibility (see [selection-tools.md](selection-tools.md)).
The shared reader supports native `AXSelectedText` controls plus Electron/Chromium text-marker ranges.
Transformations are local and synchronous in the Foundation-only `ChangeCaseEngine`.

The browser offers editable input, filtering, previews, pinned cases, four recent cases and explicit
Copy/Paste actions. Each transformation also has a direct launcher/global-shortcut action. Those 21
secondary commands ship hidden to keep launcher search compact, but users can reveal or bind them in
System → Shortcuts. Settings control source, primary action, casing/punctuation preservation,
title/sentence exceptions, retained prefix/suffix characters and enabled transformations.
