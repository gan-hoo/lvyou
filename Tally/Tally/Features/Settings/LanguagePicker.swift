import SwiftUI

/// Language menu used on the welcome screen and in Settings. Changing it asks
/// people to reopen Tally, which is when iOS applies an app's language.
struct LanguageMenu<Label: View>: View {
    @AppStorage(AppLanguage.preferenceKey) private var selectionRaw: String = AppLanguage.system.rawValue
    @State private var showReopenNotice = false
    @ViewBuilder var label: (AppLanguage) -> Label

    private var selection: AppLanguage { AppLanguage(rawValue: selectionRaw) ?? .system }

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { selection },
                set: { newValue in
                    guard newValue != selection else { return }
                    Haptics.selection()
                    if AppLanguage.select(newValue) { showReopenNotice = true }
                    selectionRaw = newValue.rawValue
                }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.title).tag(language)
                }
            } label: {
                EmptyView()
            }
        } label: {
            label(selection)
        }
        .alert(Text(verbatim: "重新打开 Tally · Reopen Tally"), isPresented: $showReopenNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: "从多任务界面上滑关闭 Tally，再重新打开即可切换语言。\nSwipe Tally away in the App Switcher and open it again to switch language.")
        }
    }
}
