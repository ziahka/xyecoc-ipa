import SwiftUI

struct ContentView: View {
    @StateObject private var accounts = AccountStore()
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru

    var body: some View {
        Group {
            if let active = accounts.activeEmail {
                NavigationStack {
                    InboxView(accounts: accounts)
                }
                .id(active)
            } else {
                LoginFlowView {
                    await accounts.onLoggedIn()
                }
            }
        }
        .tint(selectedTheme.color)
        .environment(\.locale, Locale(identifier: selectedLanguage.rawValue))
        .task { await accounts.syncActiveCache() }
    }
}
