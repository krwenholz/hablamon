import SwiftUI

@main
struct HablamonPhoneApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            PlayView(model: model)
                .overlay {
                    if model.screenOpen { ScreenTranslationView(model: model).transition(.opacity) }
                }
                .animation(Motion.appear, value: model.screenOpen)
                .modifier(PhoneTranslation(model: model))
                .task { model.start() }
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
