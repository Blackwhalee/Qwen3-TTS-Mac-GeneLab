import SwiftUI

@main
struct YujieTTSApp: App {
    @StateObject private var envManager = EnvironmentManager()
    @StateObject private var engineService = EngineService()
    @StateObject private var audioService = AudioService()
    @StateObject private var voiceLibraryStore = VoiceLibraryStore()
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if envManager.isReady {
                    MainView()
                        .environmentObject(engineService)
                        .environmentObject(audioService)
                        .environmentObject(voiceLibraryStore)
                        .environmentObject(purchaseManager)
                        .frame(minWidth: 900, minHeight: 640)
                        .onAppear {
                            engineService.startEngine()
                        }
                } else {
                    BootstrapView()
                        .environmentObject(envManager)
                }
            }
            .onAppear {
                Task { await envManager.bootstrap() }
            }
            .onDisappear {
                engineService.stopEngine()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(engineService)
                .environmentObject(purchaseManager)
        }
    }
}
