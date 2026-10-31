import Foundation

/// Only keys owned by this app are reset; OS permissions and unrelated defaults are untouched.
enum AppPreferences {
    static let policyVersion = "privacyPolicyConsentVersion"
    static let policyDate = "privacyPolicyConsentDate"
    static let defaultServings = "defaultRecipeServings"
    static let mergeInventory = "automaticallyMergeInventory"
    static let readNoticeIDs = "inAppNoticeReadIDs"
    static func validatedServings(_ value: Int) -> Int { (1...4).contains(value) ? value : 1 }
    static let resetKeys = [policyVersion, policyDate, defaultServings, mergeInventory, readNoticeIDs, "initialInventorySetupCompleted",
        "receiptConsentVersion", "receiptConsentDate", "voiceConsentVersion", "voiceConsentDate",
        "expiryNotificationsEnabled", "expiryNotificationDays", "expiryNotificationHour",
        "expiryNotificationMinute", "expiryNotificationIntroductionShown"]
    static func reset(_ defaults: UserDefaults) {
        for key in resetKeys { defaults.removeObject(forKey: key) }
    }
}
