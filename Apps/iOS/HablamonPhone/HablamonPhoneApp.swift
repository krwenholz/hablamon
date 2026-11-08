import SwiftUI

@main
struct HablamonPhoneApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            PlayView(model: model)
                .modifier(PhoneTranslation(model: model))
                .task { model.start() }
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
