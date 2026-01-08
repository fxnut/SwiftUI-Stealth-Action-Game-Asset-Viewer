import RealityKit
import UIKit
import Metal

final class RKMaterialLibraryStorage {
    private var cache: [String: any Material] = [:]
    private let bundle: Bundle
    
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }
    
    func material(materialLibrary: RKMaterialLibrary, for id: String) -> any Material {
        // Index the cache by "material_library:material_name"
        let cache_key = "\(materialLibrary.library_name):\(id)"
        if let m = cache[cache_key] { return m }
        
        var result : any Material = PhysicallyBasedMaterial()
        
        var material: RKMaterial = materialLibrary.materials.first(where: {$0.name == id}) ?? materialLibrary.default_mat
        
        if material.type == RKMaterialType.glass {
            do {
                result = try makeEnvLatLongReflectionMaterial()
            } catch {
                print("Glass material creation failed")
                material = materialLibrary.default_mat
            }
        }
        
        if material.type == RKMaterialType.physicallyBased {
            var m = PhysicallyBasedMaterial()

            m.metallic = .init(floatLiteral: material.metallic)
            m.roughness = .init(floatLiteral: material.roughness)
            m.baseColor.tint = UIColor(red: CGFloat(material.diffuse_color[0]), green: CGFloat(material.diffuse_color[1]),
                                       blue: CGFloat(material.diffuse_color[2]), alpha: CGFloat(material.diffuse_color[3]))
            
            if !material.diffuse_texture.isEmpty {
                m.baseColor.texture = texture(path: material.diffuse_texture, semantic: .color)
            }
            
            if material.opacity < 0.99 {
                m.blending = .transparent(opacity: .init(floatLiteral: material.opacity))
            }
            else {
                m.blending = .opaque
            }
            
            m.opacityThreshold = .init(floatLiteral: material.opacity_thresh)
            if !material.normal_texture.isEmpty {
                m.normal.texture = texture(path: material.normal_texture, semantic: .normal)
            }
            
            m.faceCulling = material.face_culling != 0 ? .back : .none
            //m.casts_shadow = material.casts_shadow
            result = m
        }
        
        cache[cache_key] = result
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
        let path = (path as NSString).lastPathComponent
        
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
