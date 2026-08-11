import SwiftUI

@MainActor
enum CurrencyConversionPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .currencyConversion,
                name: "Currency Conversion",
                summary: "Convert currencies inline with consented daily exchange rates.",
                systemImage: "dollarsign.arrow.circlepath",
                tint: .green),
            defaultEnabled: false,
            exportsEnabledState: true,
            readEnabled: { [weak core] in core?.currencyRates.isEnabled ?? false },
            writeEnabled: { [weak core] enabled in core?.currencyRates.setEnabled(enabled) },
            onEnable: { [weak core] in core?.currencyRates.start() },
            settingsView: { AnyView(CurrencyConversionSettingsView()) })
    }
}
