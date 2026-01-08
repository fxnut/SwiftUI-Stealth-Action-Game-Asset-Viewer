//
//  RKMaterialLibrary.swift
//  Asset Viewer
//
//  Created by Andrew Nicholas on 07/01/2026.
//
import Foundation
import UIKit

enum MaterialLibraryDecodeError: Error, CustomStringConvertible {
    case invalidFileType(String)
    case unsupportedVersion(String)
    case missingLibraryName

    var description: String {
        switch self {
        case .invalidFileType(let v): return "Invalid file_type: \(v)"
        case .unsupportedVersion(let v): return "Unsupported version: \(v)"
        case .missingLibraryName: return "Missing material library name"
        }
    }
}

struct RKMaterialLibrary : Decodable {
    let file_type: String
    let version: Int
    let library_name: String
    
    let default_mat: RKMaterial
    let materials: [RKMaterial]
    
    enum CodingKeys: String, CodingKey {
        case file_type, version, library_name, materials
        case default_mat = "default"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file_type = try c.decode(String.self, forKey: .file_type)
        
        // Validate file_type is correct
        guard file_type == "material_library" else {
            throw MaterialLibraryDecodeError.invalidFileType(file_type)
        }

        // Version is in JSON as a string, but convert it to Int
        let s = try c.decode(String.self, forKey: .version)
        guard let v = Int(s) else { throw MaterialLibraryDecodeError.unsupportedVersion(s) }
        version = v

        // Validate version == 1
        guard version == 1 else {
            throw MaterialLibraryDecodeError.unsupportedVersion(String(version))
        }
        
        library_name = try c.decode(String.self, forKey: .library_name)
        guard !library_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MaterialLibraryDecodeError.missingLibraryName
        }

        default_mat = try c.decode(RKMaterial.self, forKey: .default_mat)
        materials = try c.decode([RKMaterial].self, forKey: .materials)
    }
}

enum RKMaterialType: String, Decodable {
    case physicallyBased = "physicallybased"
    case glass
    case unknown
}

struct RKMaterial : Decodable {
    let type: RKMaterialType
    let name: String
    let metallic: Float
    let roughness: Float
    let diffuse_color: [Float]
    let diffuse_texture: String
    let opacity: Float
    let opacity_thresh: Float
    let normal_texture: String
    let face_culling: Int
    let casts_shadow: Int
    
    enum CodingKeys: String, CodingKey {
        case type, name, metallic, roughness, diffuse_color, diffuse_texture,
             opacity, opacity_thresh, normal_texture, face_culling, casts_shadow
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(RKMaterialType.self, forKey: .type) ?? RKMaterialType.unknown
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "default"
        metallic = try c.decodeIfPresent(Float.self, forKey: .metallic) ?? 0
        roughness = try c.decodeIfPresent(Float.self, forKey: .roughness) ?? 0.2
        diffuse_color = try c.decodeIfPresent([Float].self, forKey: .diffuse_color) ?? [1.0, 1.0, 1.0, 1.0]
        diffuse_texture = try c.decodeIfPresent(String.self, forKey: .diffuse_texture) ?? ""
        opacity = try c.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
        opacity_thresh = try c.decodeIfPresent(Float.self, forKey: .opacity_thresh) ?? 0
        normal_texture = try c.decodeIfPresent(String.self, forKey: .normal_texture) ?? ""
        face_culling = try c.decodeIfPresent(Int.self, forKey: .face_culling) ?? 1
        casts_shadow = try c.decodeIfPresent(Int.self, forKey: .casts_shadow) ?? 1
    }
    
}


enum MaterialLibraryLoadError: Error, CustomStringConvertible {
    case fileNotFound(name: String, ext: String)
    case decodeFailed(underlying: Error)

    var description: String {
        switch self {
        case .fileNotFound(let name, let ext):
            return "Could not find \(name).\(ext) in the app bundle."
        case .decodeFailed(let underlying):
            return "Failed to decode material library JSON: \(underlying)"
        }
    }
}

func loadMaterialLibraryFromBundle(_ filename: String, ext: String = "matlib") throws -> RKMaterialLibrary {
    let bundle: Bundle = Bundle.main
    
    guard let url = bundle.url(forResource: filename, withExtension: ext) else {
        throw MaterialLibraryLoadError.fileNotFound(name: filename, ext: ext)
    }

    let data = try Data(contentsOf: url)

    do {
        return try JSONDecoder().decode(RKMaterialLibrary.self, from: data)
    } catch {
        // This will include your MaterialLibraryDecodeError too, if thrown from init(from:)
        throw MaterialLibraryLoadError.decodeFailed(underlying: error)
    }
}
