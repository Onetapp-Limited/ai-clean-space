import SwiftUI
import AdSupport
import AppsFlyerLib
import ApphudSDK
import AppTrackingTransparency

@main
struct ai_clean_spaceApp: App {
    
    let uniqueUserID: String

    init() {
        // 1. Инициализация сервиса покупок
        _ = ApphudPurchaseService.shared
        
        // 2. Генерация/Получение Customer User ID
        let defaults = UserDefaults.standard
        let customerUserIDKey = "customer_user_id"
        
        if let storedUserID = defaults.string(forKey: customerUserIDKey) {
            uniqueUserID = storedUserID
        } else {
            uniqueUserID = UUID().uuidString
            defaults.set(uniqueUserID, forKey: customerUserIDKey)
        }
        
        // 3. Настройка AppsFlyer (Должен быть настроен до Apphud, но Apphud запущен раньше)
        let afLib = AppsFlyerLib.shared()
        afLib.customerUserID = uniqueUserID // Синхронизируем Customer ID
        afLib.appleAppID = "6753582842"
        afLib.appsFlyerDevKey = "9oYzQca8NQqjxRWtZXKADo"
        // afLib.delegate = AppsFlyerDelegateHandler.shared - УДАЛЕНО: Ненадежный метод передачи атрибуции
        
        // 4. Запуск Apphud (ДОЛЖЕН БЫТЬ ЗАПУЩЕН НЕМЕДЛЕННО)
        // Важно: Передаем тот же uniqueUserID
        Apphud.start(apiKey: "app_5Y2wecWansSDtpq7A8uX8sXUsYHEr3", userID: uniqueUserID)
        
        // 5. Запрос ATT (Асинхронно, как и было)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            requestTrackingAuthorization()
            
            Task {
                await ApphudPurchaseService.shared.fetchProducts()
            }
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
                var idfa: String? = nil
                
                if status == .authorized {
                    // IDFA доступен только после .authorized
                    idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                    // ВАЖНО: Apphud сам заберет IDFA и передаст его в AppsFlyer, если AppsFlyer еще не был запущен.
                }

                // 6. Передаем IDFA/IDFV в Apphud (наилучшая практика)
                Apphud.setDeviceIdentifiers(idfa: idfa, idfv: idfv)
                
                // 7. Запуск AppsFlyer
                // AppsFlyer должен быть запущен после того, как IDFA/ATT установлен.
                AppsFlyerLib.shared().start()
            }
        }
    }
}
