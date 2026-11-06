import SwiftUI

@main
enum MacBJLaunch {
    static func main() {
        if NvmdCommand.shouldRun {
            NvmdCommand.run()
        } else {
            MacBJApp.main()
        }
    }
}

struct MacBJApp: App {
    init() {
        NvmdShim.install()
    }

    var body: some Scene {
        let _ = LanguageStore.shared.choice
        WindowGroup(ProductName.title) {
            ContentView()
        }
        .defaultSize(width: 1180, height: 840)
        .defaultLaunchBehavior(.presented)
    }
}
