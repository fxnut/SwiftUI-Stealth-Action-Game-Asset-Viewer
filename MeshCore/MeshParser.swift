// Sources/MeshCore/MeshParser.swift
import Foundation

public struct MeshParser {
    public init() {}
    
    public func parse(data: Data) throws -> Mesh {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MeshParseError.invalidHeader("File is not valid UTF-8.")
        }
        return try parse(text: text)
    }
    
    public func parse(url: URL) throws -> Mesh {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }    
    
    public func parse(text: String) throws -> Mesh {
        print("Parsing mesh resource")
        do {
            let rawLines = text.split(whereSeparator: \.isNewline).map(String.init)
            
            // Strip comments and whitespace, but keep line numbers for errors
            var lines: [(lineNo: Int, content: String)] = []
            lines.reserveCapacity(rawLines.count)
            
            for (i, raw) in rawLines.enumerated() {
                let lineNo = i + 1
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.hasPrefix("#") { continue }
                
                // Allow inline comments: "v ... # comment"
                let content: String
                if let hash = trimmed.firstIndex(of: "#") {
                    content = String(trimmed[..<hash]).trimmingCharacters(in: .whitespaces)
                } else {
                    content = trimmed
                }
                if !content.isEmpty {
                    lines.append((lineNo, content))
                }
            }
            
            var cursor = 0
            func nextLine() throws -> (Int, String) {
                guard cursor < lines.count else { throw MeshParseError.unexpectedEOF }
                defer { cursor += 1 }
                return lines[cursor]
            }
            
            // mesh <meshName>
            let (l0, header0) = try nextLine()
            let h0 = tokenize(header0)
            guard h0.count == 2, h0[0] == "mesh" else {
                throw MeshParseError.invalidHeader("Expected `mesh <name>` at line \(l0)")
            }
            let meshName = h0[1]
            
            // version 1
            let (l1, header1) = try nextLine()
            let h1 = tokenize(header1)
            guard h1.count == 2, h1[0] == "version", let version = Int(h1[1]) else {
                throw MeshParseError.invalidHeader("Expected `version <int>` at line \(l1)")
            }
        
            // Optional metadata block (we’ll parse/skip cleanly)
            // metadata <count>
            var metadata: [String: String] = [:]
            if cursor < lines.count {
                let (ln, peek) = lines[cursor]
                let t = tokenize(peek)
                if t.first == "metadata" {
                    _ = try nextLine()
                    guard t.count == 2, let mCount = Int(t[1]), mCount >= 0 else {
                        throw MeshParseError.invalidCount(line: ln, message: "Invalid metadata count")
                    }
                    for _ in 0..<mCount {
                        let (ml, mline) = try nextLine()
                        let mt = tokenize(mline)
                        guard mt.count >= 3, mt[0] == "m" else {
                            throw MeshParseError.invalidToken(line: ml, message: "Expected `m <key> <value>`")
                        }
                        let key = mt[1]
                        let value = mt[2...].joined(separator: " ")
                        metadata[key] = value
                    }
                }
            }
            
            // vertices <count>
            let (lv, vHeader) = try nextLine()
            let vt = tokenize(vHeader)
            guard vt.count == 2, vt[0] == "vertices", let vCount = Int(vt[1]), vCount >= 0 else {
                throw MeshParseError.invalidHeader("Expected `vertices <count>` at line \(lv)")
            }
            
            var positions: [SIMD3<Float>] = []
            var normals:   [SIMD3<Float>] = []
            var uvs:       [SIMD2<Float>] = []
            var mask:      [Int32] = []
            var flags:     [Int32] = []
            positions.reserveCapacity(vCount)
            normals.reserveCapacity(vCount)
            uvs.reserveCapacity(vCount)
            mask.reserveCapacity(vCount)
            flags.reserveCapacity(vCount)
            
            for _ in 0..<vCount {
                let (l, line) = try nextLine()
                let t = tokenize(line)
                // v px py pz nx ny nz u v mask flags
                guard t.count == 11, t[0] == "v" else {
                    throw MeshParseError.invalidToken(line: l, message: "Expected vertex line: `v px py pz nx ny nz u v mask flags`")
                }
                guard
                    let px = Float(t[1]), let py = Float(t[2]), let pz = Float(t[3]),
                    let nx = Float(t[4]), let ny = Float(t[5]), let nz = Float(t[6]),
                    let uu = Float(t[7]), let vv = Float(t[8]),
                    let m  = Int32(t[9]),
                    let f  = Int32(t[10])
                else {
                    throw MeshParseError.invalidToken(line: l, message: "Vertex has invalid numeric fields")
                }
                
                positions.append(SIMD3(px, py, pz))
                normals.append(SIMD3(nx, ny, nz))
                uvs.append(SIMD2(uu, vv))
                mask.append(m)
                flags.append(f)
            }
            /*
            // Flip V if using SceneKit
            for i in 0..<uvs.count {
                uvs[i].y = 1.0 - uvs[i].y
            }
            */
            
            // triangles <count>
            let (lt, tHeader) = try nextLine()
            let tt = tokenize(tHeader)
            guard tt.count == 2, tt[0] == "triangles", let triCount = Int(tt[1]), triCount >= 0 else {
                throw MeshParseError.invalidHeader("Expected `triangles <count>` at line \(lt)")
            }
            
            var indices: [UInt32] = []
            indices.reserveCapacity(triCount * 3)
            
            for _ in 0..<triCount {
                let (l, line) = try nextLine()
                let t = tokenize(line)
                // t i0 i1 i2
                guard t.count == 4, t[0] == "t" else {
                    throw MeshParseError.invalidToken(line: l, message: "Expected triangle line: `t i0 i1 i2`")
                }
                guard let i0 = UInt32(t[1]), let i1 = UInt32(t[2]), let i2 = UInt32(t[3]) else {
                    throw MeshParseError.invalidToken(line: l, message: "Triangle has invalid integer indices")
                }
                indices.append(i0); indices.append(i1); indices.append(i2)
            }

            
            // material_library <name>
            let (lm, mlib) = try nextLine()
            let tm = tokenize(mlib)
            var materialLibName: String?
            if tm.first == "material_library" {
                guard tm.count == 2 else {
                    throw MeshParseError.invalidToken(line: lm, message: "Expected material_library <name>")
                }
                materialLibName = tm[1]
            }
            guard let materialLibName = materialLibName else {
                throw MeshParseError.invalidHeader("Missing `material_library <name>` block")
            }

            // materials <count>
            var submeshes: [Submesh] = []
            
            if cursor < lines.count {
                let (ln, peek) = lines[cursor]     // <-- lookahead ONLY
                let t = tokenize(peek)
                
                if t.first == "material_assignment" {   // (fix spelling to match your file)
                    _ = try nextLine()                  // consume the header line ONCE
                    guard t.count == 2, let smCount = Int(t[1]), smCount >= 0 else {
                        throw MeshParseError.invalidCount(line: ln, message: "Invalid submeshes count")
                    }
                    submeshes.reserveCapacity(smCount)
                    
                    
                    for _ in 0..<smCount {
                        let (sl, sline) = try nextLine()
                        let st = tokenize(sline)
                        print(st)
                        
                        
                        // m <materialId> tris <start> <end>
                        // flags: 1 = Cast Shadow
                        //        2 = Receive Shadow
                        guard st.count == 5,
                              st[0] == "m",
                              st[2] == "tris",
                              let start = Int(st[3]),
                              let end = Int(st[4])
                        else {
                            throw MeshParseError.invalidToken(line: sl, message: "Expected submesh line: `m <id> tris <start> <end>`")
                        }
                        
                        let materialId = st[1]
                        print(materialId)
                        submeshes.append(Submesh(name: materialId, materialId: materialId, triStart: start, triEnd: end, flags: 3))
                    }
                    
                }
            }
            
            
            /*var submeshes: [Submesh] = []
        
            let (ln, peek) = try nextLine()
            let t = tokenize(peek)
            print(t)
            if t.first == "material_assigment" {
                //_ = try nextLine()
                guard t.count == 2, let smCount = Int(t[1]), smCount >= 0 else {
                    throw MeshParseError.invalidCount(line: ln, message: "Invalid submeshes count")
                }
                submeshes.reserveCapacity(smCount)
                print(smCount)
                for _ in 0..<smCount {
                    let (sl, sline) = try nextLine()
                    let st = tokenize(sline)
                    print(st)
                    

                    // m <materialId> tris <start> <end>
                    // flags: 1 = Cast Shadow
                    //        2 = Receive Shadow
                    guard st.count == 8,
                          st[0] == "m",
                          st[2] == "tris",
                          let start = Int(st[3]),
                          let end = Int(st[4])
                    else {
                        throw MeshParseError.invalidToken(line: sl, message: "Expected submesh line: `m <id> tris <start> <end>`")
                    }
                    
                    let materialId = st[1]
                    print(materialId)
                    submeshes.append(Submesh(name: materialId, materialId: materialId, triStart: start, triEnd: end, flags: 3))
                }
            
            }*/
                
            let mesh = Mesh(
                name: meshName,
                version: version,
                positions: positions,
                normals: normals,
                uvs: uvs,
                mask: mask,
                flags: flags,
                indices: indices,
                submeshes: submeshes,
                materialLibraryName: materialLibName
            )
        
            // Optionally use metadata later; kept here so it’s easy to extend.
            _ = metadata    
            try MeshValidator.validate(mesh)
            print("Mesh parsed successfully")
            return mesh
        } catch {
            print("Parsing failed: ", error)
            throw error
        }
    }
    
    private func tokenize(_ line: String) -> [String] {
        // Split on whitespace; handles multiple spaces/tabs
        line.split { $0 == " " || $0 == "\t" }.map(String.init)
    }
        
}
