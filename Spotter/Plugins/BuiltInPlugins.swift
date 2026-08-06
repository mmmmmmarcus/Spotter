/// The only catalog edit needed to add a built-in plugin; each factory keeps its feature wiring local.
@MainActor
enum BuiltInPlugins {
    static func registrations(core: AppCore) -> [PluginRegistration] {
        [
            CurrencyConversionPlugin.registration(core: core),
            ClipboardPlugin.registration(core: core),
            TextReplacementPlugin.registration(core: core),
            NotePlugin.registration(core: core),
            QuicklinksPlugin.registration(core: core),
            EmojiSymbolsPlugin.registration(core: core),
            WorldClockPlugin.registration(core: core),
            KillProcessPlugin.registration(core: core),
            ChangeCasePlugin.registration(core: core),
            SelectionToolsPlugin.registration(core: core),
            ImageModificationPlugin.registration(core: core),
            QuickTimePlugin.registration(core: core),
            WindowManagementPlugin.registration(core: core),
            SystemCommandsPlugin.registration(core: core),
            MolePlugin.registration(core: core),
            CoffeePlugin.registration(core: core),
        ]
    }
}
