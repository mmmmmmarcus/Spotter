# Fix Text validation — 2026-10-30

Validated the local 1.7.30-dev worktree, based on commit 8d453c5. These changes are not part of the already published 1.7.30 release.

## Native application checks

Actual foreground Hyper+F used this Mac's configured Control+Option+Command modifiers through macOS keyboard events. Tests used unsent Grok Bot input, an isolated local Chrome HTML fixture, and a separate Figma draft. No messages were sent and no existing designs were edited.

| Surface | Selected input | Observed result |
| --- | --- | --- |
| Grok Bot composer | She go to work yesterday and forget her keys. | She went to work yesterday and forgot her keys. |
| Chrome textarea | teh mesage, inside Keep this: teh mesage. End. | Keep this: the message. End. |
| Chrome contenteditable | She have three cat and they is hungry. | She has three cats and they are hungry. |
| Figma canvas text | I has a good idea for this desgin. | I have a good idea for this design. |

The verifiable editors displayed the inline placeholder and then the answer, without a chat window or status Toast. Figma retained Inter Regular 12 and no placeholder residue. Its AX range setter had previously acknowledged selection without moving the actual editing caret; native keyboard selection fixed that mismatch.

The independent Figma draft is named `Spotter Hyper+F Test`.

## Interruption checks

- Typing `My new draft stays.` while Chrome was waiting preserved that exact draft after the model finished.
- Switching from Chrome to Grok Bot after the placeholder appeared caused no paste into Grok Bot. Returning to Chrome restored the original sentence instead of applying a stale answer.
- Background recovery deliberately waits for the original app to become active. It does not activate another app or assume that background AX writes succeeded.

## Automated checks

All 56 standalone harnesses passed. Added coverage includes native placeholder transactions, Unicode ranges, stale document protection, deferred recovery, unconfirmed writes, word-count scope selection and legacy prompt migration. Debug build and atomic installation succeeded.

These results cover the named editable controls. They do not claim compatibility with every app, read-only control, or editor implementation. Copy-only controls without a verifiable full document keep their original text until a guarded final paste.
