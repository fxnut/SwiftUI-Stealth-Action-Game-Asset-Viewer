import Foundation

public enum MeshValidator {
    public static func validate(_ mesh: Mesh) throws {
        let n = mesh.vertexCount
        guard mesh.normals.count == n else { throw MeshParseError.validationFailed("Normals count != vertex count") }
        guard mesh.uvs.count == n else { throw MeshParseError.validationFailed("UV count != vertex count") }
        guard mesh.mask.count == n else { throw MeshParseError.validationFailed("Mask count != vertex count") }
        guard mesh.flags.count == n else { throw MeshParseError.validationFailed("Flags count != vertex count") }
        
        guard mesh.indices.count % 3 == 0 else { throw MeshParseError.validationFailed("Index count is not divisible by 3") }
        
        // Index bounds
        for (i, idx) in mesh.indices.enumerated() {
            if idx >= UInt32(n) {
                throw MeshParseError.validationFailed("Index out of range at indices[\(i)] = \(idx), vertexCount=\(n)")
            }
        }
        
        // Submesh bounds
        let triCount = mesh.triangleCount
        for sm in mesh.submeshes {
            guard sm.triStart >= 0, sm.triEnd >= sm.triStart else {
                throw MeshParseError.validationFailed("Submesh \(sm.name) has invalid tri range")
            }
            guard sm.triEnd < triCount else {
                throw MeshParseError.validationFailed("Submesh \(sm.name) triEnd out of bounds (triEnd=\(sm.triEnd), triCount=\(triCount))")
            }
        }
    }
}
