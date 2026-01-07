import Foundation

public struct Mesh: Sendable {
    public var name: String
    public var version: Int
    
    public var positions: [SIMD3<Float>]
    public var normals:   [SIMD3<Float>]
    public var uvs:       [SIMD2<Float>]
    
    // mask and flags per vertex
    public var mask:  [Int32]
    public var flags: [Int32]
    
    // Triangle indices (0-based)
    public var indices: [UInt32]
    
    public var submeshes: [Submesh]
    
    public var materialLibraryName: String
    
    public init(
        name: String,
        version: Int,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        mask: [Int32],
        flags: [Int32],
        indices: [UInt32],
        submeshes: [Submesh],
        materialLibraryName: String
    ) {
        self.name = name
        self.version = version
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.mask = mask
        self.flags = flags
        self.indices = indices
        self.submeshes = submeshes
        self.materialLibraryName = materialLibraryName
    }
    
    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }
    
    mutating func reverseWinding() {
        for i in stride(from: 0, to: indices.count, by: 3) {
            indices.swapAt(i + 1, i + 2)
        }
    }    
}

public struct Submesh: Sendable {
    public var name: String
    public var materialId: String
    /// Triangle range in *triangle* units (inclusive start, inclusive end), matching your spec.
    public var triStart: Int
    public var triEnd: Int
    public var castsShadow: Bool   
    public var receivesShadow: Bool   
    
    public init(name: String, materialId: String, triStart: Int, triEnd: Int, flags: Int) {
        self.name = name
        self.materialId = materialId
        self.triStart = triStart
        self.triEnd = triEnd
        self.castsShadow = (flags & 1) > 0
        self.receivesShadow = (flags & 2) > 0        
    }
}

