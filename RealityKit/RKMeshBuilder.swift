import Foundation
import RealityKit

/*enum ShadowCategories {
    static let sun  = 1 << 0   // shadow-casting light
    static let fill = 1 << 1   // non-shadowing light
}
*/

private struct ShadowKey: Hashable {
    let casts: Bool
    let receives: Bool
}

enum MeshBuildError: Error {
    case mismatchedVertexStreams(positions: Int, normals: Int, uvs: Int)
    case indicesOutOfRange(maxIndex: UInt32, vertexCount: Int)
}

public enum RKMeshBuilder {
    /// Builds MeshResource. Submeshes become multiple geometry elements.

    public static func makeMeshNode(
        from mesh: Mesh,
        materialProvider: ((String) -> any Material)? = nil
    ) -> Entity {
        print("Processing mesh")    
        // Container node = “one mesh file”
        let root = Entity()
        root.name = mesh.name
        
        do {
            // No submeshes? Just one child node.
            guard !mesh.submeshes.isEmpty else {
                let matIndices = [UInt32](repeating: 0, count: mesh.indices.count / 3)
                let meshDescriptor = try RKMeshBuilder.makeMeshDescriptor(mesh: mesh, indices: mesh.indices, matIndices: matIndices)
                let material = materialProvider?("") ?? RKMeshBuilder.defaultMaterial()

                // Material assignment is determined by the matIndices
                let meshResource = try MeshResource.generate(from: [meshDescriptor])
                let child = ModelEntity(mesh: meshResource, materials: [material])
                // TODO: Might to address this (or just ignore)
                //child.castsShadow = true
                //child.categoryBitMask = ShadowCategories.sun | ShadowCategories.fill
                root.addChild(child)
                print("Mesh processed successfully")
                return root
            }
            
            var groupedSubmesh: [ShadowKey: [Submesh]] = [:]
            for sm in mesh.submeshes {
                let key = ShadowKey(casts: sm.castsShadow, receives: sm.receivesShadow)
                groupedSubmesh[key, default: []].append(sm)
            }
                        
            for (key, submeshArr) in groupedSubmesh {
                var allIndices: [UInt32] = []
                var perFace: [UInt32] = []   // one per triangle
                
                var materials: [any Material] = []
                var matIndexById: [String: UInt32] = [:]            

                for sm in submeshArr {
                    let startIndex = sm.triStart * 3
                    let endIndex   = (sm.triEnd * 3) + 2
                    let range = startIndex...endIndex
                    let triCount = (range.count) / 3
                                      
                    let idx: UInt32
                    if let existing = matIndexById[sm.materialId] { idx = existing }
                    else {
                        idx = UInt32(materials.count)
                        matIndexById[sm.materialId] = idx
                        materials.append(materialProvider?(sm.materialId) ?? defaultMaterial())
                    }
                    allIndices.append(contentsOf: mesh.indices[range])
                    perFace.append(contentsOf: repeatElement(idx, count: triCount)) 
                }
                precondition(allIndices.count % 3 == 0)
                precondition(perFace.count == allIndices.count / 3)
                
                var desc = MeshDescriptor()
                desc.positions = MeshBuffer(mesh.positions)
                desc.normals = MeshBuffer(mesh.normals)
                desc.textureCoordinates = MeshBuffer(mesh.uvs)
                desc.primitives = .triangles(allIndices)
                desc.materials = .perFace(perFace)
                
                let meshResource = try MeshResource.generate(from: [desc])
                let child = ModelEntity(mesh: meshResource, materials: materials)                

                print("models:", meshResource.contents.models.count)
                for (i, model) in meshResource.contents.models.enumerated() {
                    print(" model[\(i)] parts:", model.parts.count)
                }
                print("materials passed:", materials.count)
                
                child.name = "mesh_part_cast\(key.casts)_recv\(key.receives)"
                
                child.components.set(DynamicLightShadowComponent(castsShadow: key.casts))
                //child.castsShadow = key.casts
                
                // TODO: This doesn't work in RealityKit. Probably need to do a custom shader
                
                // Receive shadows (workaround) via categories:
                // - Receives: include sun category (and fill too if you want)
                // - Not receive: exclude sun; include fill so it still looks lit
                //child.categoryBitMask = key.receives
                //? (ShadowCategories.sun | ShadowCategories.fill)
                //: ShadowCategories.fill
                
                root.addChild(child)

            }
            print("Mesh processed successfully")
        } catch MeshBuildError.mismatchedVertexStreams(let p, let n, let u) {
            print("Vertex stream mismatch: positions=\(p) normals=\(n) uvs=\(u)")
        } catch MeshBuildError.indicesOutOfRange(let maxIndex, let vertexCount) {
            print("Index out of range: maxIndex=\(maxIndex) vertexCount=\(vertexCount)")
        } catch {
            print("Unexpected mesh build error:", error)
        }        
        return root
    }    
    
    private static func makeMeshDescriptor(mesh: Mesh, indices: [UInt32], matIndices: [UInt32]) throws -> MeshDescriptor {
        // Validate point data sizes match
        guard mesh.positions.count == mesh.normals.count,
              mesh.positions.count == mesh.uvs.count
        else { 
            throw MeshBuildError.mismatchedVertexStreams(
                positions: mesh.positions.count,
                normals: mesh.normals.count,
                uvs: mesh.uvs.count
            )    
        }
        
        // Validate indices in range
        if let maxIndex = indices.max(), maxIndex >= UInt32(mesh.positions.count) {
            throw MeshBuildError.indicesOutOfRange(
                maxIndex: maxIndex,
                vertexCount: mesh.positions.count
            )
        }
        
        var desc = MeshDescriptor()
        desc.positions = MeshBuffer(mesh.positions)
        desc.normals = MeshBuffer(mesh.normals)
        desc.textureCoordinates = MeshBuffer(mesh.uvs)
        desc.materials = .perFace(matIndices)
        desc.primitives = .triangles(indices)
        return desc
    }
    
    private static func defaultMaterial() -> PhysicallyBasedMaterial {
        let m = PhysicallyBasedMaterial()
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
