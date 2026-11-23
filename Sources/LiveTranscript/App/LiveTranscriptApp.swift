import AppKit
import SwiftUI

@main
struct LiveTranscriptApp: App {
    @NSApplicationDelegateAdaptor(LiveTranscriptDelegate.self) private var delegate

    var body: some Scene {
        Window("会听", id: "portrait-transcript") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 412, height: 667)
        .commands {
            CommandMenu("转写") {
                Button(delegate.model.phase.buttonTitle) { delegate.model.toggle() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(delegate.model.phase == .stopping)
                Button(delegate.model.phase.offersResume ? "继续转写" : "暂停转写") {
                    delegate.model.pauseOrResume()
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!delegate.model.phase.canPauseOrResume)
            }
        }
    }
}

@MainActor
final class LiveTranscriptDelegate: NSObject, NSApplicationDelegate {
    let model = RecorderModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model.observeMicrophones()
        if let file = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.resourceURL?.appending(path: file),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.phase != .idle else { return .terminateNow }
        Task {
            await model.stopAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
