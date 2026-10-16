import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "GeoSpoof", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        if model.busy {
            let alert = NSAlert()
            alert.messageText = "An iPhone operation is in progress"
            alert.informativeText = "Wait for it to finish before quitting."
            alert.runModal()
            return .terminateCancel
        }
        guard model.pendingID != nil else { return .terminateNow }
        Task {
            if await model.reset() { sender.reply(toApplicationShouldTerminate: true) }
            else {
                let alert = NSAlert()
                alert.messageText = "Your iPhone may still be using a simulated location"
                alert.informativeText = "Reconnect your iPhone and reset its location. If you quit now, GeoSpoof will remember to offer Reset next time."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit Anyway")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
}

@main
struct GeoSpoofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        Window("GeoSpoof", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 560)
                .task {
                    model.presentWelcomeIfNeeded()
                    await model.refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { break }
                        await model.refresh()
                    }
                }
        }
        .defaultSize(width: 1080, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Button("GeoSpoof Help") { model.showHelp() }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh iPhone Connection") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.busy)
                Button("Stop Spoofing") { Task { await model.reset() } }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.busy || model.pendingID == nil)
            }
        }
    }
}
