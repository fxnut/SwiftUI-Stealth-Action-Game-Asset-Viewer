import RealityKit
/*
final class BuildingInstancer {
    private var renderEntities: [ModelEntity] = []
    private var instanceData: [LowLevelInstanceData] = []
    
    init(buildingPrefab: Entity, instanceCount: Int) throws {
        for child in buildingPrefab.children {
            // Only instance children that actually render
            guard let model = child.components[ModelComponent.self] else { continue }
            
            let renderEntity = ModelEntity()
            renderEntity.components.set(model)
            
            let data = try LowLevelInstanceData(instanceCount: instanceCount)
            
            var mic = MeshInstancesComponent()
            mic[partIndex: 0] = .init(data: data)   // assume one part
            renderEntity.components.set(mic)
            
            renderEntities.append(renderEntity)
            instanceData.append(data)
        }
    }
    
    func addToScene(_ parent: Entity) {
        for e in renderEntities { parent.addChild(e) }
    }
    
    func setTransforms(_ transforms: [Transform]) {
        guard let first = instanceData.first else { return }
        precondition(transforms.count == first.instanceCount)
        
        // Same instance transforms written into each instanced render entity
        for data in instanceData {
            data.withMutableTransforms { out in
                for i in out.indices {
                    out[i] = transforms[i].matrix
                }
            }
        }
    }
}
*/
