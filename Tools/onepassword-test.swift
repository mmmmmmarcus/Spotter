// Compile with `OnePasswordTypes.swift`; see docs/development.md. Never executes `op`.
import Foundation

@main
struct OnePasswordTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        // Item list parsing — the shape `op item list --long --format=json` returns.
        let listJSON = Data(
            """
            [
              {"id": "b", "title": "zebra.org", "category": "LOGIN", "vault": {"id": "v1", "name": "Private"},
               "additional_information": "zebra@example.com",
               "urls": [{"href": "https://old.zebra.org", "primary": false}, {"href": "https://zebra.org", "primary": true}]},
              {"id": "a", "title": "Apple", "category": "LOGIN", "vault": {"id": "v1", "name": "Private"},
               "additional_information": "maki@example.com", "urls": [{"href": "https://apple.com"}]},
              {"id": "c", "title": "Server Key", "category": "SSH_KEY", "favorite": true,
               "vault": {"id": "v2", "name": "Work"}, "additional_information": "—"},
              {"id": "d", "title": "Wi-Fi", "category": "WIRELESS_ROUTER", "vault": {"id": "v1"}}
            ]
            """.utf8)
        let items = OnePasswordParser.parseItems(listJSON)
        check("the item list parses", items != nil)
        check("all items survive", items?.count == 4)
        check("favorites sort first", items?.first?.id == "c")
        check("the rest sort by title", items?.map(\.id) == ["c", "a", "d", "b"])
        check("a login's username is its additional information", items?[1].username == "maki@example.com")
        check("a non-login never claims a username", items?[0].username == nil)
        check("the em-dash placeholder is not a username", items?.first { $0.id == "c" }?.username == nil)
        check("the primary URL wins over the first", items?.last?.websiteURL == "https://zebra.org")
        check("a URL without a primary flag still resolves", items?[1].websiteURL == "https://apple.com")
        check("a missing vault name reads as empty", items?.first { $0.id == "d" }?.vaultName == "")
        check("garbage parses to nil, not a crash", OnePasswordParser.parseItems(Data("nope".utf8)) == nil)

        // Filtering — every token must land somewhere in the item's visible metadata.
        let all = items ?? []
        check("an empty query returns everything", OnePasswordParser.filtered(all, query: "  ").count == 4)
        check("title matching", OnePasswordParser.filtered(all, query: "apple").map(\.id) == ["a"])
        check("username matching", OnePasswordParser.filtered(all, query: "zebra@").map(\.id) == ["b"])
        check("vault matching", OnePasswordParser.filtered(all, query: "work").map(\.id) == ["c"])
        check("category-label matching", OnePasswordParser.filtered(all, query: "ssh").map(\.id) == ["c"])
        check(
            "every token must match",
            OnePasswordParser.filtered(all, query: "apple work").isEmpty)

        // Category presentation.
        check("known categories have symbols", OnePasswordCategory.symbol(for: "CREDIT_CARD") == "creditcard")
        check("unknown categories fall back to a key", OnePasswordCategory.symbol(for: "SOMETHING_NEW") == "key")
        check("labels read as words", OnePasswordCategory.label(for: "SOCIAL_SECURITY_NUMBER") == "Social Security Number")

        // Action availability mirrors 1Password 8: logins everything, passwords no username, rest open-only.
        check(
            "logins offer the full action set",
            OnePasswordItemAction.available(forCategory: "LOGIN") == OnePasswordItemAction.allCases)
        check(
            "passwords drop the username actions",
            !OnePasswordItemAction.available(forCategory: "PASSWORD").contains(.copyUsername)
                && !OnePasswordItemAction.available(forCategory: "PASSWORD").contains(.pasteUsername))
        check(
            "a secure note views or opens, nothing else",
            OnePasswordItemAction.available(forCategory: "SECURE_NOTE") == [.view, .openInApp])
        check(
            "the preferred primary applies when available",
            OnePasswordItemAction.primary(preferred: .copyPassword, category: "LOGIN") == .copyPassword)
        check(
            "an unavailable preference falls back to the item view",
            OnePasswordItemAction.primary(preferred: .copyUsername, category: "PASSWORD") == .view)
        check(
            "every category can view",
            ["LOGIN", "PASSWORD", "SECURE_NOTE", "CREDIT_CARD"].allSatisfy {
                OnePasswordItemAction.available(forCategory: $0).contains(.view)
            })
        check(
            "paste actions know they paste",
            OnePasswordItemAction.pastePassword.isPaste && !OnePasswordItemAction.copyPassword.isPaste)
        check(
            "OTP actions resolve by type, not field",
            OnePasswordItemAction.copyOneTimePassword.field == nil
                && OnePasswordItemAction.copyOneTimePassword.isOneTimePassword)

        // CLI invocations — the exact argv each feature runs.
        check(
            "the list read stays plain — --long trips op's desktop-app timeout on big vaults",
            OnePasswordCLI.listItemsArguments == ["item", "list", "--format=json"])
        check(
            "a field read uses a secret reference",
            OnePasswordCLI.readArguments(vaultID: "v1", itemID: "i1", field: "password")
                == ["read", "op://v1/i1/password"])
        check(
            "an OTP read scopes to the vault",
            OnePasswordCLI.oneTimePasswordArguments(itemID: "i1", vaultID: "v1")
                == ["item", "get", "i1", "--vault", "v1", "--otp"])
        check(
            "generate is a dry run that saves nothing",
            OnePasswordCLI.generatePasswordArguments(length: 20, digits: true, symbols: true)
                == ["item", "create", "--dry-run", "--category", "Password",
                    "--generate-password=letters,digits,symbols,20", "--format=json"])
        check(
            "generate honors disabled character classes",
            OnePasswordCLI.generatePasswordArguments(length: 12, digits: false, symbols: false)
                == ["item", "create", "--dry-run", "--category", "Password",
                    "--generate-password=letters,12", "--format=json"])
        check(
            "deep links carry account, vault and item",
            OnePasswordCLI.viewItemURL(accountID: "ACC", vaultID: "v1", itemID: "i1")
                == "onepassword://view-item/?a=ACC&v=v1&i=i1")
        check(
            "deep links survive a missing account",
            OnePasswordCLI.viewItemURL(accountID: nil, vaultID: "v1", itemID: "i1")
                == "onepassword://view-item/?v=v1&i=i1")

        // Item view — the `op item get --format=json` shape, secrets masked by the render layer.
        let detailJSON = Data(
            """
            {"id": "a", "title": "Apple", "category": "LOGIN", "vault": {"id": "v1", "name": "Private"},
             "additional_information": "maki@example.com",
             "urls": [{"href": "https://apple.com", "primary": true}, {"href": "https://icloud.com"}],
             "fields": [
               {"id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": "maki@example.com", "reference": "op://x"},
               {"id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": "s3cret!", "reference": "op://y"},
               {"id": "notesPlain", "type": "STRING", "purpose": "NOTES", "label": "notesPlain", "reference": "op://z"},
               {"id": "onetimepassword", "type": "OTP", "label": "one-time password", "value": "otpauth://totp/x", "totp": "123456"},
               {"id": "custom", "type": "STRING", "label": "License", "value": "ABC", "section": {"id": "s1", "label": "Extras"}}
             ]}
            """.utf8)
        let detail = OnePasswordParser.parseItemDetail(detailJSON)
        check("the item view parses", detail != nil)
        check("the summary rides along", detail?.item.title == "Apple" && detail?.item.vaultID == "v1")
        check("empty-value fields drop out", detail?.fields.count == 4)
        check("field order follows op", detail?.fields.map(\.id) == ["username", "password", "onetimepassword", "custom"])
        check("an OTP field carries its current code", detail?.fields[2].value == "123456")
        check("OTP and concealed fields render masked", detail?.fields[1].isConcealed == true && detail?.fields[2].isConcealed == true)
        check("plain fields render open", detail?.fields[0].isConcealed == false)
        check("section labels survive", detail?.fields[3].sectionLabel == "Extras")
        check("all websites list, primary first as given", detail?.websites == ["https://apple.com", "https://icloud.com"])
        check("username fields get the person symbol", detail?.fields[0].symbol == "person")
        check("detail garbage parses to nil", OnePasswordParser.parseItemDetail(Data("no".utf8)) == nil)
        let bareOTP = OnePasswordParser.parseItemDetail(Data(
            #"{"id":"b","title":"T","category":"LOGIN","vault":{"id":"v"},"fields":[{"id":"onetimepassword","type":"OTP","label":"one-time password"}]}"#.utf8))
        check(
            "an OTP field with nothing held keeps its row — copy re-fetches",
            bareOTP?.fields.count == 1 && bareOTP?.fields[0].isOneTimePassword == true
                && bareOTP?.fields[0].value == "")
        check(
            "the item view fetch scopes to the vault",
            OnePasswordCLI.itemDetailArguments(itemID: "i1", vaultID: "v1")
                == ["item", "get", "i1", "--vault", "v1", "--format=json"])

        // Account and generated-password payloads.
        check(
            "the account id parses",
            OnePasswordParser.parseAccountID(Data(#"{"id": "ACC", "domain": "x"}"#.utf8)) == "ACC")
        let generated = Data(
            #"{"fields": [{"id": "notesPlain"}, {"id": "password", "value": "s3cret!"}]}"#.utf8)
        check("the generated password parses", OnePasswordParser.parseGeneratedPassword(generated) == "s3cret!")
        check(
            "a missing password parses to nil",
            OnePasswordParser.parseGeneratedPassword(Data(#"{"fields": []}"#.utf8)) == nil)

        // stderr handling — `op` log prefixes strip, and locked sessions are recognized.
        check(
            "the log prefix strips",
            OnePasswordParser.errorMessage(
                fromStderr: "[ERROR] 2026/08/28 20:00:00 authorization prompt dismissed, please try again")
                == "authorization prompt dismissed, please try again")
        check(
            "empty stderr still reads as an error",
            OnePasswordParser.errorMessage(fromStderr: "  ") == "1Password CLI reported an error.")
        check(
            "a dismissed prompt reads as locked",
            OnePasswordParser.indicatesLockedSession("authorization prompt dismissed, please try again"))
        check(
            "a signed-out account reads as locked",
            OnePasswordParser.indicatesLockedSession("account is not signed in, run `op signin`"))
        check(
            "an app-connection failure reads as locked",
            OnePasswordParser.indicatesLockedSession("error connecting to desktop app"))
        check(
            "an unanswered authorization reads as locked",
            OnePasswordParser.indicatesLockedSession("authorization timeout"))
        check(
            "an ordinary failure does not read as locked",
            !OnePasswordParser.indicatesLockedSession("\"nope\" isn't an item"))
        check(
            "op's desktop-app timeout reads as a timeout",
            OnePasswordParser.indicatesTimeout(
                "Retrieving all items from the \"Private\" vault timed out - the request took longer than 30 seconds to respond"))
        check(
            "an ordinary failure does not read as a timeout",
            !OnePasswordParser.indicatesTimeout("\"nope\" isn't an item"))
        check(
            "a timeout does not read as locked",
            !OnePasswordParser.indicatesLockedSession(
                "Retrieving all items from the \"Private\" vault timed out"))

        let window = Date(timeIntervalSince1970: 1_700_000_010)
        check(
            "an OTP fetched in the current window is still current",
            OnePasswordOTP.codeStillCurrent(
                fetchedAt: window, now: Date(timeIntervalSince1970: 1_700_000_025)))
        check(
            "an OTP from the previous window is stale",
            !OnePasswordOTP.codeStillCurrent(
                fetchedAt: window, now: Date(timeIntervalSince1970: 1_700_000_045)))
        check(
            "a fetch after now never reads as current",
            !OnePasswordOTP.codeStillCurrent(
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_025), now: window))
        check(
            "the boundary second starts a new window",
            !OnePasswordOTP.codeStillCurrent(
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_039),
                now: Date(timeIntervalSince1970: 1_700_000_040)))

        if failures > 0 {
            print("\n\(failures) failure(s)")
            exit(1)
        }
        print("\nAll 1Password checks passed")
    }
}
