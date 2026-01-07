import UIKit
import RealityKit
import Combine
import simd

final class GameViewController: UIViewController {
    private let arView = ARView(frame: .zero)
    private var cancellables = Set<AnyCancellable>()
    
    private let resourceName = "tile_residential_building_A_mesh_1x1_0"
    private let resourceExt  = "txt"
    
    private var azimuth: Float = -.pi * 0.25
    private var elevation: Float = -.pi * 0.20
    private var radius: Float = 40.0
    
    private var lastPanPoint: CGPoint = .zero
    
    private let world = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let yawNode = Entity()
    private let pitchNode = Entity()    
    
    private let materials = RKMaterialLibrary()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("-- Building Scene -------------------------")
        
        view.addSubview(arView)
        arView.frame = view.bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.cameraMode = .nonAR
        
        arView.scene.addAnchor(world)

        setupEnvironment()    
        setupCamera(parent: world)
        updateCamera()
        do {
            try loadMesh(parent: world)
        } catch {
            print("Failed to load mesh:", String(reflecting: error))
            showError(title: "Failed to load mesh:", error: error)
        }
        addSunLight(to: world)
        addTileGrid(to: world)
        
        // Per-frame update hook
        arView.scene.subscribe(to: SceneEvents.Update.self) { event in
            // game tick
        }.store(in: &cancellables)

        setupGestures()         
    }    
    
    private func showError(title: String, error: Error) {
        let alert = UIAlertController(
            title: title,
            message: String(reflecting: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }    
    
    func setupEnvironment() {        
        do {
            // Note: To make a realityenv file, you need to build it on the Mac using the XCode project
            // I made for this purpose. You then copy it to the Resources folder of this package.
            let env = try EnvironmentResource.load(named: "suburb_street_hdr_e")
            
            arView.environment.lighting.resource = env
            arView.environment.background = .skybox(env)
            arView.environment.lighting.intensityExponent = 0.02
            
        } catch {
            print("❌ Failed to load environment: \(error)")
            // Turn off image-based lighting (IBL)
            arView.environment.lighting.resource = nil
            
            // Optional: make sure it contributes nothing even if something sets it later
            arView.environment.lighting.intensityExponent = -100   // effectively “off” (very dark)
            
            // Turn off any skybox/background image
            arView.environment.background = .color(.black)                    
        }        
    }
    
    private func loadMesh(parent: Entity) throws {        
        if let url = findResourceURL(name: resourceName, ext: resourceExt) {
            var mesh = try MeshParser().parse(url: url)
            mesh.reverseWinding()

            let entity = RKMeshBuilder.makeMeshNode(from: mesh) { materialId in
                self.materials.material(for: materialId)
            }
            
            entity.name = "previewMesh"
            //node.castsShadow = true
            //centerNodePivot(node)
            
            // Replace existing
            //scene.rootNode.childNodes.filter { $0.name == "previewMesh" }.forEach { $0.removeFromParentNode() }
            
            parent.addChild(entity)
        }
    }
        
    func setupCamera(parent: Entity) {
        camera.camera.near = 0.1
        camera.camera.far = 5000
        camera.camera.fieldOfViewInDegrees = 55
        
        parent.addChild(yawNode)
        yawNode.addChild(pitchNode)
        pitchNode.addChild(camera)        
    }
    
    func addSunLight(to anchor: Entity) {
        let sun = DirectionalLight()
        
        // Light settings
        sun.light = DirectionalLightComponent(
            color: .white,
            intensity: 5000,        // tweak for your scene scale
            isRealWorldProxy: false
        )
        
        // Shadows (key bit)
        // Start with a reasonably large maximumDistance for “city scale”, then dial down for quality.
        sun.shadow = .init(maximumDistance: 200, depthBias: 1.0) 
        
        // Shine down at ~60° with a slight yaw.
        let pitch = simd_quatf(angle: -.pi * 0.33, axis: [1, 0, 0])
        let yaw   = simd_quatf(angle:  .pi * 0.25, axis: [0, 1, 0])
        sun.transform.rotation = yaw * pitch
        
        anchor.addChild(sun)
    }    
        
    func addFloor(to anchor: Entity, size: Float = 200, y: Float = 0) {
        // Thin box “slab”
        let mesh = MeshResource.generateBox(size: [size, 0.1, size])
        
        var mat = PhysicallyBasedMaterial()
        mat.baseColor.tint = .darkGray
        mat.roughness = 0.9
        mat.metallic = 0.0
        
        let floor = ModelEntity(mesh: mesh, materials: [mat])
        floor.position = [0, y - 0.05, 0] // half thickness down so top surface sits at y
        
        // Optional: collision for raycasts / taps (and physics if you add it)
        floor.generateCollisionShapes(recursive: false)
        
        // Optional: make it a static physics body so dynamic objects can rest on it
        floor.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
        
        anchor.addChild(floor)
    }    
    
    
    func addTileGrid(to anchor: Entity, nx: Int = 3, ny: Int = 3, tileSize: Float = 14, gap: Float = 0.05, thickness: Float = 0.1) {
        
        let root = Entity()
        
        let boxMesh = MeshResource.generateBox(size: [tileSize-gap, thickness, tileSize-gap])
        
        var mat = PhysicallyBasedMaterial()
        mat.baseColor.tint = .darkGray
        mat.roughness = 0.9
        mat.metallic = 0.0
        
        // Center the grid around (0,0,0)
        let halfx = Float(nx - 1) * tileSize * 0.5
        let halfy = Float(ny - 1) * tileSize * 0.5
        
        for row in 0..<ny {
            for col in 0..<nx {
                let e = ModelEntity(mesh: boxMesh, materials: [mat])
                e.position = SIMD3<Float>(Float(col) * tileSize - halfx, -thickness*0.5, Float(row) * tileSize - halfy)
                root.addChild(e)
            }
        }        
        anchor.addChild(root)
    }    
    
    private func updateCamera() {
        // clamp pitch so we never hit the singularity
        let maxPitch: Float = (.pi / 2) - 0.01
        elevation = min(max(elevation, -maxPitch), maxPitch)
        
        yawNode.transform.rotation = simd_quatf(angle: azimuth, axis: [0, 1, 0])
        
        // SceneKit: pitchNode.eulerAngles.x = elevation
        pitchNode.transform.rotation = simd_quatf(angle: elevation, axis: [1, 0, 0])
        
        // SceneKit: cameraNode.position.z = radius
        // (local translation relative to pitchEntity)
        camera.position = [0, 0, radius]        
    }
    
    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        arView.addGestureRecognizer(pan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        arView.addGestureRecognizer(pinch)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        arView.addGestureRecognizer(doubleTap)
    }
    
    
    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let p = g.translation(in: arView)
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
    
    func findResourceURL(name: String, ext: String) -> URL? {
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
}
