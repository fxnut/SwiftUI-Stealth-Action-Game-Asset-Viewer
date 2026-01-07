import UIKit
import SceneKit

func deg2rad(_ d: Float) -> Float { d * .pi / 180 }

final class TurntablePreviewViewController: UIViewController {
    
    // MARK: - Tweakables
    private let resourceName = "tile_residential_building_A_mesh_1x1_0"

    private let resourceExt  = "txt"
    
    private var azimuth: Float = -.pi * 0.25
    private var elevation: Float = -.pi * 0.20
    private var radius: Float = 12.0
    
    private var lastPanPoint: CGPoint = .zero
    
    // MARK: - SceneKit bits
    private let scnView = SCNView(frame: .zero)
    private let scene = SCNScene()
    
    private let cameraNode = SCNNode()
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()    
    
    private let materials = MaterialLibrary()
        
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupView()
        setupScene()
        setupGestures()
        
        do {
            try loadMesh()
        } catch {
            showError(String(describing: error))
        }
        
        updateCamera()
    }
    
    private func setupView() {
        scnView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scnView)
        
        NSLayoutConstraint.activate([
            scnView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scnView.topAnchor.constraint(equalTo: view.topAnchor),
            scnView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        scnView.scene = scene
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.rendersContinuously = true
        scnView.isPlaying = true
    }
    
    private func setupScene() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 5000
        cameraNode.camera?.fieldOfView = 55

        scene.rootNode.addChildNode(yawNode)
        yawNode.addChildNode(pitchNode)
        pitchNode.addChildNode(cameraNode)        
                
        cameraNode.position = SCNVector3(0, 0, radius) // camera looks down its -Z, so this faces origin        
        
        scene.lightingEnvironment.contents = materials.image("suburb_street_e.png")
        scene.lightingEnvironment.intensity = 0.3

        scene.rootNode.addChildNode(makeReflectionProbeSphere())
        
        //scene.background.contents = materials.image("suburb_street_e.png")                
        // Ambient
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 0 //50
        scene.rootNode.addChildNode(ambient)
        
        // Directional 1
        let directional_1 = SCNNode()
        directional_1.light = SCNLight()
        directional_1.light?.type = .directional
        directional_1.light?.intensity = 600        
        directional_1.position = SCNVector3(20, 40, 30)
        directional_1.look(at: SCNVector3Zero)
        directional_1.light?.categoryBitMask = ShadowCategories.sun
        
        directional_1.light?.castsShadow = true
        directional_1.light?.orthographicScale = 80.0
        directional_1.light?.zFar = 600.0
        directional_1.light?.zNear = 1.0
        
        //directional_1.light?.shadowCascadeCount = 4   // or 4
        //directional_1.light?.shadowCascadeSplittingFactor = 0.2
        
        directional_1.light?.automaticallyAdjustsShadowProjection = false
        directional_1.light?.shadowMode = .forward               // quality vs perf tradeoff
        directional_1.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        directional_1.light?.shadowSampleCount = 16               // softer = more samples
        directional_1.light?.shadowRadius = 1                     // blur amount
        directional_1.light?.shadowColor = UIColor(white: 0, alpha: 0.6)
        directional_1.light?.shadowBias = 1.0e-4                  // tweak if you see acne/peter-panning     
        scene.rootNode.addChildNode(directional_1)

        // Directional 2
        let directional_2 = SCNNode()
        directional_2.light = SCNLight()
        directional_2.light?.type = .directional
        directional_2.light?.intensity = 0 //200        
        directional_2.position = SCNVector3(-20, 10, -30)
        directional_2.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(directional_2)
        
        scnView.pointOfView = cameraNode        

        // Floor (optional)
        let floor = SCNFloor()
        floor.reflectivity = 0.0
        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        fm.roughness.contents = 0.8
        fm.metalness.contents = 0.0        
        floor.materials = [fm]
        
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -5.001, 0)
        floorNode.castsShadow = false
        scene.rootNode.addChildNode(floorNode)

    }
    
    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        scnView.addGestureRecognizer(pan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        scnView.addGestureRecognizer(pinch)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scnView.addGestureRecognizer(doubleTap)
    }
    
    private func loadMesh() throws {
        guard let url = findResourceURL(name: resourceName, ext: resourceExt) else {
            throw NSError(domain: "Turntable", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find resource \(resourceName).\(resourceExt)."
            ])
        }
        
        var mesh = try MeshParser().parse(url: url)
        mesh.reverseWinding()
        
        let node = SceneKitBuilder.makeMeshNode(from: mesh) { materialId in
            self.materials.material(for: materialId)
        }

        node.name = "previewMesh"
        node.castsShadow = true
        centerNodePivot(node)
        
        // Replace existing
        scene.rootNode.childNodes
            .filter { $0.name == "previewMesh" }
            .forEach { $0.removeFromParentNode() }
        
        scene.rootNode.addChildNode(node)
        
        // Fit camera to mesh
        let (minB, maxB) = node.boundingBox
        let sx = maxB.x - minB.x
        let sy = maxB.y - minB.y
        let sz = maxB.z - minB.z
        let diag = sqrt(sx*sx + sy*sy + sz*sz)
        radius = max(2.0, Float(diag) * 1.4)
        updateCamera()
    }
    
    private func findResourceURL(name: String, ext: String) -> URL? {
        // Playgrounds App / SwiftUI app bundle resources
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        
        // Sometimes Playgrounds sticks resources in other bundles
        for b in Bundle.allBundles {
            if let u = b.url(forResource: name, withExtension: ext) { return u }
        }
        
        // Last fallback: if you dragged the file into the project and it’s accessible by path
        // (rare, but harmless to keep)
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent("\(name).\(ext)")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        
        return nil
    }    
    
    private func centerNodePivot(_ node: SCNNode) {
        let (minB, maxB) = node.boundingBox
        let cx = (minB.x + maxB.x) * 0.5
        let cy = (minB.y + maxB.y) * 0.5
        let cz = (minB.z + maxB.z) * 0.5
        node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)
    }
    
    private func updateCamera() {
        // clamp pitch so we never hit the singularity
        let maxPitch: Float = (.pi / 2) - 0.01
        elevation = min(max(elevation, -maxPitch), maxPitch)
        
        yawNode.eulerAngles.y = azimuth
        pitchNode.eulerAngles.x = elevation
        cameraNode.position.z = radius
    }
    
    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let p = g.translation(in: scnView)
        if g.state == .began { lastPanPoint = p }
        
        let dx = Float(p.x - lastPanPoint.x)
        let dy = Float(p.y - lastPanPoint.y)
        lastPanPoint = p
        
        let sensitivity: Float = 0.01
        azimuth   += -dx * sensitivity
        elevation += -dy * sensitivity
        
        updateCamera()
    }    
    
    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            let s = Float(g.scale)
            radius = max(0.2, min(radius / s, 10_000))
            g.scale = 1.0
            updateCamera()
        }
    }
    
    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        azimuth = -.pi * 0.25
        elevation = -.pi * 0.20
        updateCamera()
    }
    
    private func showError(_ message: String) {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.numberOfLines = 0
        label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        label.text = "Preview error:\n\(message)"
        label.backgroundColor = UIColor(white: 0.0, alpha: 0.6)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .left
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
    }
}

/// A simple “probe” sphere you can drop into your scene to verify reflections.
/// - Position: (0, 15, 0)
/// - Radius: 1.0
func makeReflectionProbeSphere() -> SCNNode {
    let sphere = SCNSphere(radius: 1.0)
    sphere.segmentCount = 96
    
    let mat = SCNMaterial()
    
    // Use PBR (recommended with scene.lightingEnvironment)
    mat.lightingModel = .physicallyBased
    mat.metalness.contents = 1.0     // chrome
    mat.roughness.contents = 0.0     // sharp reflections
    
    // Optional: helps you see the shape even if lighting is minimal
    mat.diffuse.contents = UIColor.white
    
    sphere.firstMaterial = mat
    
    let node = SCNNode(geometry: sphere)
    node.position = SCNVector3(2, 10, 9)
    node.name = "ReflectionProbeSphere"
    return node
}

// Usage:
// scene.rootNode.addChildNode(makeReflectionProbeSphere())
