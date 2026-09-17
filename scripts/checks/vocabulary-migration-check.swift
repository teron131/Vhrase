// Verifies retired replacements become vocabulary exactly once in preferences and imported customization.

import Foundation

@main
struct VocabularyMigrationCheck {
  static func main() throws {
    let rules =
      "cloud fair => Cloudflare\nx AI -> xAI\nopen ai = OpenAI\ninvalid\n => ignored\nempty -> "
    let expected = "OpenAI\nCloudflare\nxAI"
    precondition(
      DictationSettings.migratingVocabulary("OpenAI", replacementRules: rules) == expected)

    // Preserve delimiter priority and target punctuation from previously valid rules.
    for (rule, target) in [
      ("name => value => suffix", "value => suffix"),
      ("name -> value -> suffix", "value -> suffix"),
      ("name = value = suffix", "value = suffix"),
      ("name = alias -> preferred => final", "final"),
      ("發音 😀 => 正字 👩🏽‍💻 = 保留", "正字 👩🏽‍💻 = 保留"),
    ] {
      precondition(DictationSettings.migratingVocabulary("", replacementRules: rule) == target)
    }

    let suite = "Vhrase.VocabularyMigrationCheck.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("OpenAI", forKey: "keyterms")
    defaults.set(rules, forKey: "replacementRules")
    let store = SettingsStore(defaults: defaults)
    let migrated = store.load()
    precondition(migrated.keyterms == expected)
    precondition(defaults.object(forKey: "replacementRules") == nil)
    precondition(defaults.string(forKey: "keyterms") == expected)
    precondition(store.load() == migrated)
    store.save(migrated)
    precondition(store.load() == migrated)

    var settings = DictationSettings.defaults
    settings.keyterms = "OpenAI"
    let encoded = try JSONEncoder().encode(CustomizationSnapshot(settings: settings))
    var export = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    var oldSettings = export["settings"] as! [String: Any]
    oldSettings["replacementRules"] = rules
    export["settings"] = oldSettings
    let imported = try JSONDecoder().decode(
      CustomizationSnapshot.self, from: JSONSerialization.data(withJSONObject: export))
    precondition(imported.settings.keyterms == expected)
    let currentExport = try JSONEncoder().encode(imported)
    precondition(!String(decoding: currentExport, as: UTF8.self).contains("replacementRules"))
    let roundTrip = try JSONDecoder().decode(CustomizationSnapshot.self, from: currentExport)
    precondition(roundTrip == imported)
    print("vocabulary migration ok")
  }
}
