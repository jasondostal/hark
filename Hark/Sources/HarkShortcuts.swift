import AppIntents

/// Shows Hark's actions in Shortcuts and the Action Button picker with no setup.
struct HarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartListeningIntent(),
                    phrases: ["Start listening with \(.applicationName)",
                              "Listen with \(.applicationName)",
                              "What's that sound in \(.applicationName)"],
                    shortTitle: "Start Listening", systemImageName: "ear")
    }
}
