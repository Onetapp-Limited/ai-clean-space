import SwiftUI
import AdSupport
import AppsFlyerLib
import ApphudSDK
import AppTrackingTransparency

@main
struct ai_clean_spaceApp: App {
    init() {
        _ = ApphudPurchaseService.shared
        
        let defaults = UserDefaults.standard
        let customerUserIDKey = "customer_user_id"
        let uniqueUserID: String
        if let storedUserID = defaults.string(forKey: customerUserIDKey) {
            uniqueUserID = storedUserID
        } else {
            uniqueUserID = UUID().uuidString
            defaults.set(uniqueUserID, forKey: customerUserIDKey)
        }
        
        // Настройка AppsFlyer
        let afLib = AppsFlyerLib.shared()
        afLib.customerUserID = uniqueUserID
        afLib.appleAppID = "6753582842"
        afLib.appsFlyerDevKey = "9oYzQca8NQqjxRWtZXKADo"
        afLib.delegate = AppsFlyerDelegateHandler.shared
        
        // --- Запрос ATT ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            requestTrackingAuthorization()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
    
    private func requestTrackingAuthorization() {
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                let idfv = UIDevice.current.identifierForVendor?.uuidString ?? ""
                let idfa: String? = (status == .authorized) ? ASIdentifierManager.shared().advertisingIdentifier.uuidString : nil
                
                Apphud.setDeviceIdentifiers(idfa: idfa, idfv: idfv)
                Apphud.start(apiKey: "app_5Y2wecWansSDtpq7A8uX8sXUsYHEr3")
                
                AppsFlyerLib.shared().start()
            }
        }
    }
}

class AppsFlyerDelegateHandler: NSObject, AppsFlyerLibDelegate {
    static let shared = AppsFlyerDelegateHandler()

    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        Apphud.setAttribution(
            data: ApphudAttributionData(rawData: data),
            from: .appsFlyer,
            identifer: AppsFlyerLib.shared().getAppsFlyerUID()
        ) { _ in }
    }

    func onConversionDataFail(_ error: Error) {
        print("[AFSDK] \(error.localizedDescription)")
        Apphud.setAttribution(
            data: ApphudAttributionData(rawData: ["error": error.localizedDescription]),
            from: .appsFlyer,
            identifer: AppsFlyerLib.shared().getAppsFlyerUID()
        ) { _ in }
    }
}

