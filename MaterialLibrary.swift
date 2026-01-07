import SceneKit
import UIKit

final class MaterialLibrary {
    private var cache: [String: SCNMaterial] = [:]
    private let bundle: Bundle
    
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }
    
    func material(for id: String) -> SCNMaterial {
        if let m = cache[id] { return m }
        
        let m = SCNMaterial()
        m.name = id
        m.lightingModel = .physicallyBased
        
        // Good defaults
        m.metalness.contents = 0.0
        m.roughness.contents = 0.85
        
        var tile = false
        
        // Map IDs -> textures
        switch id {
        case "brick_wall":
            m.diffuse.contents   = image("brick_wall_t.png")
            m.roughness.contents = 0.2
            m.metalness.contents = 0.0
            tile = true
            // m.normal.contents    = image("window_normal")
            // m.emission.contents = image("window_emissive")
        case "floor_tiles":
            m.diffuse.contents   = image("floor_tiles_t.png")
            m.roughness.contents = 0.2
            m.metalness.contents = 0.0
            tile = true
        case "railings":
            m.diffuse.contents   = image("railing_at.png")      
            m.metalness.contents = 0.0
            m.roughness.contents = 0.2            
            m.isDoubleSided = true
            tile = true
        case "white_wall":
            m.diffuse.contents   = image("white_wall_t.png")
            m.roughness.contents = 0.2
            m.metalness.contents = 0.0
            tile = true
        case "windows":
            m.diffuse.contents   = image("city_atlas.png")
            m.roughness.contents = 0.2
            m.metalness.contents = 0.0
            m.normal.contents = image("city_atlas_n.png")
            tile = false
        case "glass":
            
            m.metalness.contents = 1.0
            m.roughness.contents = 0.05    
            m.diffuse.contents = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.1)
            m.transparency = 0.15
            m.blendMode = .alpha  
            m.transparencyMode = .dualLayer
            m.isDoubleSided = true                                                       
        default:
            break
        }
        
        if m.diffuse.contents == nil {
            print("❌ diffuse.contents is nil for material \(id)")
        }
        
        if tile {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
        }
        
        cache[id] = m
        return m
    }
    
    public func image(_ path: String) -> UIImage? {
        // Allow either "texture/foo.png" or "foo.png"
        let url = resourceURL(for: path)
        
        if let url {
            if let img = UIImage(contentsOfFile: url.path) {
                return img
            } else {
                print("❌ Found file but UIImage failed to load: \(url.path)")
                return nil
            }
        } else {
            print("❌ Resource not found in bundle: \(path)")
            // Optional: list what *is* in that folder once
            dumpTextureFolderOnce()
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
