import SwiftUI

@main
struct TranscriberApp: App {
    @State private var viewModel = TranscriptViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel) {
                openWindow(id: "transcriber-main")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Transcriber", id: "transcriber-main") {
            TranscriptWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 380, height: 480)
        .windowResizability(.contentSize)
    }

    private var menuBarIcon: String {
        switch viewModel.state {
        case .recording: "mic.fill"
        case .paused: "mic.slash"
        default: "mic"
        }
    }
}
