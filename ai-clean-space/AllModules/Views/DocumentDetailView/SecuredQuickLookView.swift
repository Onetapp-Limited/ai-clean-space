import SwiftUI
import QuickLook
import Foundation

struct SecuredQuickLookView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        
        controller.navigationItem.setHidesBackButton(true, animated: false)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.refreshCurrentPreviewItem()
    }
    
    // Обновлен тип возвращаемого значения
    func makeCoordinator() -> QuickLookCoordinator { // Переименовано PreviewCoordinator
        QuickLookCoordinator(self)
    }
    
    // Переименованный class Coordinator
    class QuickLookCoordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate { // Переименовано PreviewCoordinator
        var parent: SecuredQuickLookView // Обновлен тип
        
        init(_ parent: SecuredQuickLookView) { // Обновлен тип
            self.parent = parent
            super.init()
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as QLPreviewItem
        }
        
        func previewControllerWillDismiss(_ controller: QLPreviewController) {}
    }
}

