import SwiftUI
import Combine
import SafariServices
import StoreKit

enum ResurcesUrlsConstants {
    // todo Замените эти URL на реальные
    static let licenseAgreementURL: String = "https://docs.google.com/document/d/1OwaR-nw8bOiLE0QM2t7mgsZhH_piBTMcfOrvcov3a8M/edit?usp=sharing"
    static let privacyPolicyURL: String = "https://docs.google.com/document/d/1ODflJsIb9M4ciQiYU6ZWQZ1ETMbvjW6-ifpNjVzgUSE/edit?usp=sharing"
    static let termsURL: String = "https://docs.google.com/document/d/1OwaR-nw8bOiLE0QM2t7mgsZhH_piBTMcfOrvcov3a8M/edit?usp=sharing"
    static let feedBackEmail: String = "feedback@yourapp.com"
}

final class SettingsViewModel: ObservableObject {
    
    @Published var isPasscodeEnabledInApp: Bool = false
    @Published var isFaceIDInAppEnabled: Bool = false
    @Published var isSecretSpacePasscodeEnabled: Bool = true
    @Published var isSecretSpaceFaceIDEnabled: Bool = true
    
    func rateUsTapped() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    func licenseAgreementTapped() {
        guard let url = URL(string: ResurcesUrlsConstants.licenseAgreementURL) else { return }
        UIApplication.shared.open(url)
    }
    
    func privacyPolicyTapped() {
        guard let url = URL(string: ResurcesUrlsConstants.privacyPolicyURL) else { return }
        UIApplication.shared.open(url)
    }
    
    func sendFeedbackTapped() {
        let subject = "Feedback"
        let body = ""
        let mailtoString = "mailto:\(ResurcesUrlsConstants.feedBackEmail)?subject=\(subject)&body=\(body)"
        
        if let mailtoUrl = URL(string: mailtoString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
            UIApplication.shared.open(mailtoUrl)
        }
    }
}
