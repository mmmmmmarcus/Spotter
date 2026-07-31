import Foundation

extension Bundle {
    /// The installed product name from CFBundleDisplayName/CFBundleName in the generated Info.plist.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Spotter"
    }
}
