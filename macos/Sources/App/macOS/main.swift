import AppKit
import Cocoa
import GhosttyKit

// Pre-set LANGUAGE from macOS preferred languages so that gettext can find
// the correct translation catalog even when LANG is set to a different locale
// (e.g. LANG=en_US.UTF-8 but the user prefers zh_CN).
//
// ghostty_init() calls ensureLocale() which only calls setLangFromCocoa() when
// LANG is unset. setLangFromCocoa() is also where LANGUAGE is set from
// preferredLanguages. If LANG is already set by a parent process (e.g. a
// shell), setLangFromCocoa() is skipped entirely and LANGUAGE is never set,
// causing gettext to fall back to the LANG locale (English).
//
// We set LANGUAGE here before ghostty_init() so it is always available.
if ProcessInfo.processInfo.environment["LANGUAGE"] == nil {
    let preferred = Locale.preferredLanguages
    if !preferred.isEmpty {
        // Convert BCP-47 tags (e.g. "zh-Hans-CN") to POSIX locale names
        // (e.g. "zh_CN") that gettext understands.
        func bcp47ToPosix(_ tag: String) -> String {
            // zh-Hans-* → zh_CN/zh_SG, zh-Hant-* → zh_TW/zh_HK/zh_MO
            let parts = tag.split(separator: "-", maxSplits: 3).map(String.init)
            if parts.count >= 2 && parts[0] == "zh" {
                let script = parts[1]
                let region = parts.count >= 3 ? parts[2] : ""
                if script == "Hans" { return region == "SG" ? "zh_SG" : "zh_CN" }
                if script == "Hant" {
                    if region == "MO" { return "zh_MO" }
                    if region == "HK" { return "zh_HK" }
                    return "zh_TW"
                }
            }
            // General case: replace "-" with "_" and drop any extra subtags
            let lang = parts[0]
            let region = parts.count >= 2 ? parts[1] : ""
            if region.isEmpty || region.count > 4 { return lang }
            return "\(lang)_\(region)"
        }
        let langValue = preferred.map { bcp47ToPosix($0) }.joined(separator: ":")
        setenv("LANGUAGE", langValue, 0)
    }
}

// Initialize Ghostty global state. We do this once right away because the
// CLI APIs require it and it lets us ensure it is done immediately for the
// rest of the app.
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
    Ghostty.logger.critical("ghostty_init failed")

    // We also write to stderr if this is executed from the CLI or zig run
    switch Ghostty.launchSource {
    case .cli, .zig_run:
        let stderrHandle = FileHandle.standardError
        stderrHandle.write(
            "Ghostty failed to initialize! If you're executing Ghostty from the command line\n" +
            "then this is usually because an invalid action or multiple actions were specified.\n" +
            "Actions start with the `+` character.\n\n" +
            "View all available actions by running `ghostty +help`.\n")
        exit(1)

    case .app:
        // For the app we exit immediately. We should handle this case more
        // gracefully in the future.
        exit(1)
    }
}

// This will run the CLI action and exit if one was specified. A CLI
// action is a command starting with a `+`, such as `ghostty +boo`.
ghostty_cli_try_action()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
