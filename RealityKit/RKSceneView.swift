import SwiftUI
import UIKit

struct RKSceneView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController()
    }
    
    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {
        // No-op
    }
}

