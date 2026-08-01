# Change Case plugin

Change Case implements the 21 transformations exposed by the Raycast extension: camel, capital,
constant, dot, header, lower, lower-first, no-case, kebab, upper-kebab, Pascal, Pascal-snake, path,
random, sentence, snake, alternating, swap, title, upper and upper-first.

The preferred input can be selected text or the clipboard; an empty preferred source falls back to
the other. Reading selection and pasting use Accessibility only after the user invokes an action.
Transformations are local and synchronous in the Foundation-only `ChangeCaseEngine`.

The browser offers editable input, filtering, previews, pinned cases, four recent cases and explicit
Copy/Paste actions. Each transformation also has a direct launcher/global-shortcut action. Those 21
secondary commands ship hidden to keep launcher search compact, but users can reveal or bind them in
System → Shortcuts. Settings control source, primary action, casing/punctuation preservation,
title/sentence exceptions, retained prefix/suffix characters and enabled transformations.
