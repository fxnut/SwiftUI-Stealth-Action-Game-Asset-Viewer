import SwiftUI
import UIKit

struct TurntableSceneView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TurntablePreviewViewController {
        TurntablePreviewViewController()
    }
    
    func updateUIViewController(_ uiViewController: TurntablePreviewViewController, context: Context) {
        // No-op
    }
}

