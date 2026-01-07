import RealityKit
import UIKit
import Metal

final class RKMaterialLibrary {
    private var cache: [String: any Material] = [:]
    private let bundle: Bundle
    
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }
    
    func material(for id: String) -> any Material {
        if let m = cache[id] { return m }
        
        var result : any Material = PhysicallyBasedMaterial()
        
        // Map IDs -> textures
        switch id {
        case "brick_wall":
            var m = PhysicallyBasedMaterial()
            m.baseColor.texture = texture(path: "brick_wall_t.png", semantic: .color)
            m.metallic = 0.0
            m.roughness = 0.2
            // m.normal.contents    = image("window_normal")
            // m.emission.contents = image("window_emissive")
            result = m
        case "floor_tiles":            
            var m = PhysicallyBasedMaterial()
            m.baseColor.texture = texture(path: "floor_tiles_t.png", semantic: .color)
            m.metallic = 0.0
            m.roughness = 0.2
            result = m
        case "railings":
            var m = PhysicallyBasedMaterial()            
            m.baseColor.texture = texture(path: "railing_at.png", semantic: .color)      
            m.metallic = 0.0
            m.roughness = 0.2            
            // Enable transparency
            m.blending = .transparent(opacity: 1.0)
            // Cutout: pixels with alpha < threshold are discarded
            m.opacityThreshold = 0.5
            m.faceCulling = .none
            result = m
        case "white_wall":            
            var m = PhysicallyBasedMaterial()
            m.baseColor.texture = texture(path: "white_wall_t.png", semantic: .color)           
            m.metallic = 0.0
            m.roughness = 0.2
            result = m
        case "city_atlas":
            var m = PhysicallyBasedMaterial()
            m.baseColor.texture = texture(path: "city_atlas.png", semantic: .color)       
            m.metallic = 0.0
            m.roughness = 0.2
            m.normal.texture = texture(path: "city_atlas_n.png", semantic: .normal)
            result = m     
        case "glass":
            do {
                let m = try makeEnvLatLongReflectionMaterial()
                result = m
            } catch {
                print("Failed to make glass material")
                print("Error:", error)
                print("Type:", String(reflecting: type(of: error)))
                var m = PhysicallyBasedMaterial()
                m.baseColor.tint = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1.0)
                m.blending = .transparent(opacity: 0.25)
                m.faceCulling = .none
                
                m.metallic = 1.0
                m.roughness = 0.05
                result = m                
            }
        default:
            var m = PhysicallyBasedMaterial()
            m.baseColor.tint = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)       
            result = m     
            break
        }
        
        //if m.baseColor.texture == nil {
            // print("❌ diffuse.contents is nil for material \(id)")
        //}
        cache[id] = result
        return result
    }
        
    func makeEnvLatLongReflectionMaterial() throws -> CustomMaterial {
        let device = MTLCreateSystemDefaultDevice()!
        
        guard let libURL = Bundle.main.url(forResource: "customShaders", withExtension: "metallib") else {
            print("Missing customShaders.metallib in bundle")
            throw NSError(domain: "Shader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing metallib"])
        }
        var mat: CustomMaterial?
        
        do {
            let library = try device.makeLibrary(URL: libURL)
            
            let surface = CustomMaterial.SurfaceShader(
                named: "envLatLongReflectionSurface",
                in: library
            )
            mat = try CustomMaterial(
                surfaceShader: surface,
                geometryModifier: nil,
                lightingModel: .unlit
            )
        } catch {
            print("Failed to load metallib or shader:", error)
        }            
                
        // Provide the env texture to the shader via the custom slot:
        let env = try TextureResource.load(named: "suburb_street_e") // lat-long/equirect image
        mat!.custom.texture = .init(env)
        mat!.custom.value = SIMD4<Float>(6.0, 0.25, 0.0, 0.0)
        
        mat!.blending = .transparent(opacity: 1.0)
        mat!.opacityThreshold = 0.0
        mat?.writesDepth = false
        mat?.faceCulling = .none
        return mat!
    }
    
    
    private func buildShaderLibrary() throws -> MTLLibrary {
        let shaderURL = Bundle.main.url(forResource: "shaders", withExtension: "txt")!
        let source = try! String(contentsOf: shaderURL, encoding: .utf8)
    
        let device = MTLCreateSystemDefaultDevice()!
    
        let opt = MTLCompileOptions()
        opt.enableLogging = true
        // Those two options are important.
        opt.libraryType = .dynamic
        opt.installName = "shaders.metallib"
        
        // We need to create MTLLibrary...
        let library = try device.makeLibrary(source: source, options: opt)
        /*
        // ...that we convert into dynamic library...
        let dynLib = try device.makeDynamicLibrary(library: library)
        
        // ...that we can serialize to disk as metallib file...
        let tempUrl : URL = .temporaryDirectory.appending(
            component: dynLib.installName, directoryHint: .notDirectory)
        try dynLib.serialize(to: tempUrl)
        
        // ... that we can finally read as ShaderLibrary
        let sLib = ShaderLibrary(url: tempUrl)*/
        return library
}
    
    private func makeGlassMaterial() throws -> CustomMaterial {
        //let device = MTLCreateSystemDefaultDevice()!
        //let library = device.makeDefaultLibrary()!
        let library = try buildShaderLibrary()
        
        let surface = CustomMaterial.SurfaceShader(named: "unlitGlassShader", in: library)
        //let geom = CustomMaterial.GeometryModifier(named: "myGeometryModifier", in: library) // optional
        
        let mat = try CustomMaterial(
            surfaceShader: surface,
            geometryModifier: nil,
            lightingModel: .unlit              // .lit / .clearcoat / .unlit
        )
        return mat
    }
    
    private func texture(path: String, semantic: TextureResource.Semantic) -> MaterialParameters.Texture? {
        guard let url = resourceURL(for: path) else {
            print("❌ Resource not found in bundle: \(path)")
            dumpTextureFolderOnce()
            return nil
        }
        
        guard let img = UIImage(contentsOfFile: url.path), let cg = img.cgImage else {
            print("❌ Found file but UIImage/CGImage failed to load: \(url.path)")
            return nil
        }
        
        do {
            let tex = try TextureResource(
                image: cg,
                withName: (path as NSString).lastPathComponent,
                options: .init(semantic: semantic)
            )
            return MaterialParameters.Texture(tex)
        } catch {
            print("❌ TextureResource creation failed for \(url.path): \(error)")
            return nil
        }
    }
        
    private func resourceURL(for path: String) -> URL? {
        let ns = path as NSString
        let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension
        let base = ns.deletingPathExtension
        let dir = (base as NSString).deletingLastPathComponent
        let name = (base as NSString).lastPathComponent
        
        // If no folder provided, dir will be "."
        let subdir = (dir == "." || dir.isEmpty) ? nil : dir
        
        return bundle.url(forResource: name, withExtension: ext, subdirectory: subdir)
    }
    
    private var didDump = false
    private func dumpTextureFolderOnce() {
        guard !didDump else { return }
        didDump = true
        
        if let urls = bundle.urls(forResourcesWithExtension: "png", subdirectory: "texture") {
            print("✅ PNGs in bundle/texture:")
            for u in urls { print("  - \(u.lastPathComponent)") }
        } else {
            print("⚠️ No PNGs found under bundle subdirectory 'texture'")
        }
    }    
}
