import SwiftUI

struct CurrencyConversionSettingsView: View {
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(title: "Currency Conversion") {
            Section("Exchange Rates") {
                SettingsRow(title: "Download Exchange Rates") {
                    // The switch is the consent act — the plugin is always on, but nothing is
                    // contacted until this is.
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { currencyRates.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    currencyRates.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if currencyRates.isEnabled {
                    SettingsRow(title: "Exchange Rates", subtitle: ratesStatus) {
                        Button("Update Now") {
                            refreshing = true
                            Task {
                                let landed = await currencyRates.refreshNow()
                                refreshFailed = !landed
                                refreshing = false
                            }
                        }
                        .disabled(refreshing)
                    }
                }
            }
        }
        .sheet(isPresented: $askingConsent) {
            CurrencyConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    currencyRates.setEnabled(true)
                })
        }
    }

    private var ratesStatus: String {
        if refreshing { return "Updating…" }
        if refreshFailed { return "Couldn't reach \(CurrencyRateStore.provider). Try again." }
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return "\(CurrencyRateStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(CurrencyRateStore.provider) · updated \(stamp). Refreshes daily."
    }
}

private struct CurrencyConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Turn on currency conversion?")
                .font(.headline)

            Text(
                "Spotter downloads exchange rates from \(CurrencyRateStore.provider) once a day and "
                    + "keeps a copy on your Mac. No account, no identifiers, nothing you type. "
                    + "Turning it off deletes the cached rates."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: CurrencyRateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(CurrencyRateStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
