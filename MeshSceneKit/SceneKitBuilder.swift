import Foundation
import SceneKit

enum ShadowCategories {
    static let sun  = 1 << 0   // shadow-casting light
    static let fill = 1 << 1   // non-shadowing light
}

private struct ShadowKey: Hashable {
    let casts: Bool
    let receives: Bool
}

public enum SceneKitBuilder {
    /// Builds SCNGeometry. Submeshes become multiple geometry elements.
    /*
    public static func makeGeometry(
        from mesh: Mesh,
        materialProvider: ((String) -> SCNMaterial)? = nil
    ) -> SCNGeometry {
        
        let vertexCount = mesh.vertexCount
        
        let posData = packedDataFromSIMD3(mesh.positions)
        let nrmData = packedDataFromSIMD3(mesh.normals)
        let uvData  = packedDataFromSIMD2(mesh.uvs)
        
        let posSource = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12 // Assumes you're using the packedDataFromSIMD3() 
        )
        
        let nrmSource = SCNGeometrySource(
            data: nrmData,
            semantic: .normal,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12 // Assumes you're using the packedDataFromSIMD3()
        )
        
        let uvSource = SCNGeometrySource(
            data: uvData,
            semantic: .texcoord,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 8 // Assumes you're using the packedDataFromSIMD2()
        )
        
        // Build elements
        let elements: [SCNGeometryElement]
        if mesh.submeshes.isEmpty {
            elements = [makeElement(indices: mesh.indices)]
        } else {
            elements = mesh.submeshes.map { sm in
                let startIndex = sm.triStart * 3
                let endIndex   = (sm.triEnd * 3) + 2
                let slice = Array(mesh.indices[startIndex...endIndex])
                return makeElement(indices: slice)
            }
        }
        
        let geom = SCNGeometry(sources: [posSource, nrmSource, uvSource], elements: elements)
        
        // Materials: one per element (materialId maps to index)
        if mesh.submeshes.isEmpty {
            geom.materials = [materialProvider?("") ?? defaultMaterial()]
        } else {
            geom.materials = mesh.submeshes.map { sm in
                materialProvider?(sm.materialId) ?? defaultMaterial()
            }
        }
        
        return geom
    }
    */    
    
    public static func makeMeshNode(
        from mesh: Mesh,
        materialProvider: ((String) -> SCNMaterial)? = nil
    ) -> SCNNode {
        
        let vertexCount = mesh.vertexCount
        
        let posData = SceneKitBuilder.packedDataFromSIMD3(mesh.positions)
        let nrmData = SceneKitBuilder.packedDataFromSIMD3(mesh.normals)
        let uvData  = SceneKitBuilder.packedDataFromSIMD2(mesh.uvs)
        
        let posSource = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12
        )
        
        let nrmSource = SCNGeometrySource(
            data: nrmData,
            semantic: .normal,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 12
        )
        
        let uvSource = SCNGeometrySource(
            data: uvData,
            semantic: .texcoord,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 8
        )
        
        let sources = [posSource, nrmSource, uvSource]
        
        // Container node = “one mesh file”
        let root = SCNNode()
        root.name = mesh.name
        
        // No submeshes? Just one child node.
        guard !mesh.submeshes.isEmpty else {
            let element = SceneKitBuilder.makeElement(indices: mesh.indices)
            let geom = SCNGeometry(sources: sources, elements: [element])
            geom.materials = [materialProvider?("") ?? SceneKitBuilder.defaultMaterial()]
            
            let child = SCNNode(geometry: geom)
            child.castsShadow = true
            child.categoryBitMask = ShadowCategories.sun | ShadowCategories.fill
            root.addChildNode(child)
            return root
        }
        
        // Group submeshes by (castsShadow, receivesShadow)
        var grouped: [ShadowKey: [(SCNGeometryElement, SCNMaterial)]] = [:]
        grouped.reserveCapacity(4)
        
        for sm in mesh.submeshes {
            let startIndex = sm.triStart * 3
            let endIndex   = (sm.triEnd * 3) + 2
            let slice = Array(mesh.indices[startIndex...endIndex])
            let element = SceneKitBuilder.makeElement(indices: slice)
            
            let mat = materialProvider?(sm.materialId) ?? SceneKitBuilder.defaultMaterial()
            
            let key = ShadowKey(casts: sm.castsShadow, receives: sm.receivesShadow)
            grouped[key, default: []].append((element, mat))
        }
        
        // Build a child node per group
        for (key, items) in grouped {
            let elements = items.map { $0.0 }
            let materials = items.map { $0.1 }
            
            let geom = SCNGeometry(sources: sources, elements: elements)
            geom.materials = materials
            
            let child = SCNNode(geometry: geom)
            child.name = "mesh_part_cast\(key.casts)_recv\(key.receives)"
            
            // Cast shadows is node-level
            child.castsShadow = key.casts
            
            // Receive shadows (workaround) via categories:
            // - Receives: include sun category (and fill too if you want)
            // - Not receive: exclude sun; include fill so it still looks lit
            child.categoryBitMask = key.receives
            ? (ShadowCategories.sun | ShadowCategories.fill)
            : ShadowCategories.fill
            
            print(child.categoryBitMask)
            print(elements)
            root.addChildNode(child)
        }

        return root
    }    
    
    private static func makeElement(indices: [UInt32]) -> SCNGeometryElement {
        let indexData = indices.withUnsafeBytes { Data($0) }
        return SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
    }
    
    private static func defaultMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // Keep it simple; caller can override via materialProvider
        return m
    }
    
    private static func dataFromSIMD3(_ a: [SIMD3<Float>]) -> Data {
        a.withUnsafeBytes { Data($0) }
    }
    
    private static func dataFromSIMD2(_ a: [SIMD2<Float>]) -> Data {
        a.withUnsafeBytes { Data($0) }
    }
    
    // Makes an array of vector (xyz) with stride 12 (not 16 from dataFromSIMD3() )
    private static func packedDataFromSIMD3(_ a: [SIMD3<Float>]) -> Data {
        var floats: [Float] = []
        floats.reserveCapacity(a.count * 3)
        for v in a { floats.append(v.x); floats.append(v.y); floats.append(v.z) }
        return floats.withUnsafeBytes { Data($0) }
    }
    
    // Makes an array of vector (xy) with stride 8 
    // (probably 8 from dataFromSIMD2() as well, but this makes sure )    
    private static func packedDataFromSIMD2(_ a: [SIMD2<Float>]) -> Data {
        var floats: [Float] = []
        floats.reserveCapacity(a.count * 2)
        for v in a { floats.append(v.x); floats.append(v.y) }
        return floats.withUnsafeBytes { Data($0) }
    }    
    
}
