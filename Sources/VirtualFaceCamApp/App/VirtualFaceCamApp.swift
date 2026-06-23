import SwiftUI

@main
struct VirtualFaceCamApp: App {
    @StateObject private var viewModel = AppViewModel(
        container: DependencyContainer.live
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
    }
}
