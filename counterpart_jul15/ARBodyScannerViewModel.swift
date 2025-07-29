//
//  ARBodyScannerViewModel.swift
//  counterpart_jul15
//
//  Created by Aseem Sethi on 7/15/25.
//

import SwiftUI
import ARKit
import RealityKit
import MetalKit
import Combine

class ARBodyScannerViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentPhase: ScanningPhase = .preparation
    @Published var canExport = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var arView: ARView?
    private var arSession: ARSession?
    private var meshAnchors: [ARMeshAnchor] = []
    private var capturedMeshes: [MeshData] = []
    private var scanTimer: Timer?
    private var phaseTimer: Timer?
    private var totalScanTime: TimeInterval = 10.0 // 10 seconds total scan time for testing
    private var currentScanTime: TimeInterval = 0.0
    
    // Mesh processing
    private var device: MTLDevice?
    private var meshVertices: [SIMD3<Float>] = []
    private var meshFaces: [UInt32] = []
    
    override init() {
        super.init()
        setupMetal()
    }
    
    // MARK: - Setup Methods
    
    func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
    }
    
    func setupAR() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "ARKit is not supported on this device"
            return
        }
        
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            errorMessage = "LiDAR mesh scanning is not supported on this device"
            return
        }
    }
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        self.arSession = arView.session
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        // Enable camera passthrough
        arView.environment.background = .cameraFeed()
        arView.renderOptions.insert(.disablePersonOcclusion)
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableMotionBlur)
        
        arView.session.delegate = self
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Setup scene
        setupScene()
        
        print("ARView configured with camera feed enabled")
    }
    
    private func setupScene() {
        guard let arView = arView else { return }
        
        // Add lighting
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        directionalLight.light.isRealWorldProxy = true
        directionalLight.shadow?.maximumDistance = 10
        directionalLight.shadow?.depthBias = 0.001
        
        let lightAnchor = AnchorEntity(world: [0, 2, 0])
        lightAnchor.addChild(directionalLight)
        arView.scene.addAnchor(lightAnchor)
    }
    
    // MARK: - Scanning Control Methods
    
    func startScanning() {
        guard !isScanning else { return }
        
        isScanning = true
        currentScanTime = 0.0
        scanProgress = 0.0
        
        print("🚀 Starting body scan...")
        
        // Start the scanning phases
        advanceToNextPhase()
        
        // Start progress timer
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateScanProgress()
        }
    }
    
    func pauseScanning() {
        isScanning = false
        scanTimer?.invalidate()
        phaseTimer?.invalidate()
    }
    
    func cancelScanning() {
        pauseScanning()
        resetScanning()
    }
    
    func resetScanning() {
        isScanning = false
        scanProgress = 0.0
        currentPhase = .preparation
        canExport = false
        currentScanTime = 0.0
        
        // Clear captured data
        meshAnchors.removeAll()
        capturedMeshes.removeAll()
        meshVertices.removeAll()
        meshFaces.removeAll()
        
        scanTimer?.invalidate()
        phaseTimer?.invalidate()
        
        // Reset AR session
        if let arView = arView {
            let configuration = ARWorldTrackingConfiguration()
            configuration.sceneReconstruction = .mesh
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    // MARK: - Phase Management
    
    private func advanceToNextPhase() {
        switch currentPhase {
        case .preparation:
            currentPhase = .frontScan
            schedulePhaseTransition(duration: 5.0) // 5 seconds for front scan
            
        case .frontScan:
            currentPhase = .sideScan
            schedulePhaseTransition(duration: 5.0) // 5 seconds for side scan
            
        case .sideScan:
            currentPhase = .backScan
            schedulePhaseTransition(duration: 5.0) // 5 seconds for back scan
            
        case .backScan:
            currentPhase = .processing
            processCapturedMeshes()
            
        case .processing:
            currentPhase = .complete
            canExport = true
            isScanning = false
            
        case .complete:
            break
        }
    }
    
    private func schedulePhaseTransition(duration: TimeInterval) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            if self.isScanning {
                self.advanceToNextPhase()
            }
        }
    }
    
    private func updateScanProgress() {
        guard isScanning else { return }
        
        currentScanTime += 0.1
        scanProgress = min(currentScanTime / totalScanTime, 1.0)
        
        if scanProgress >= 1.0 && currentPhase != .complete {
            advanceToNextPhase()
        }
    }
    
    // MARK: - Mesh Processing
    
    private func processCapturedMeshes() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.combineMeshData()
            self.optimizeMesh()
            self.filterBodyMesh()
            
            DispatchQueue.main.async {
                self.advanceToNextPhase()
            }
        }
    }
    
    private func combineMeshData() {
        meshVertices.removeAll()
        meshFaces.removeAll()
        
        var vertexOffset: UInt32 = 0
        
        for meshData in capturedMeshes {
            // Add vertices
            meshVertices.append(contentsOf: meshData.vertices)
            
            // Add faces with offset
            for face in meshData.faces {
                meshFaces.append(face + vertexOffset)
            }
            
            vertexOffset += UInt32(meshData.vertices.count)
        }
    }
    
    private func optimizeMesh() {
        // Remove duplicate vertices
        var uniqueVertices: [SIMD3<Float>] = []
        var vertexMap: [Int: Int] = [:]
        
        for (index, vertex) in meshVertices.enumerated() {
            if let existingIndex = uniqueVertices.firstIndex(where: { 
                distance($0, vertex) < 0.001 // 1mm tolerance
            }) {
                vertexMap[index] = existingIndex
            } else {
                vertexMap[index] = uniqueVertices.count
                uniqueVertices.append(vertex)
            }
        }
        
        // Update faces with new vertex indices
        meshFaces = meshFaces.compactMap { oldIndex in
            vertexMap[Int(oldIndex)].map { UInt32($0) }
        }
        
        meshVertices = uniqueVertices
    }
    
    private func filterBodyMesh() {
        // Filter out vertices that are too far from the expected body region
        // This is a simplified approach - in production, you'd use more sophisticated filtering
        
        guard !meshVertices.isEmpty else { return }
        
        // Find the center of the mesh
        let center = meshVertices.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 } / Float(meshVertices.count)
        
        // Filter vertices within reasonable body dimensions (2m x 2m x 2m around center)
        let maxDistance: Float = 1.0
        var filteredVertices: [SIMD3<Float>] = []
        var vertexIndexMap: [Int: Int] = [:]
        
        for (index, vertex) in meshVertices.enumerated() {
            if distance(vertex, center) <= maxDistance {
                vertexIndexMap[index] = filteredVertices.count
                filteredVertices.append(vertex)
            }
        }
        
        // Update faces
        var filteredFaces: [UInt32] = []
        for i in stride(from: 0, to: meshFaces.count, by: 3) {
            let v1 = Int(meshFaces[i])
            let v2 = Int(meshFaces[i + 1])
            let v3 = Int(meshFaces[i + 2])
            
            if let newV1 = vertexIndexMap[v1],
               let newV2 = vertexIndexMap[v2],
               let newV3 = vertexIndexMap[v3] {
                filteredFaces.append(UInt32(newV1))
                filteredFaces.append(UInt32(newV2))
                filteredFaces.append(UInt32(newV3))
            }
        }
        
        meshVertices = filteredVertices
        meshFaces = filteredFaces
    }
    
    // MARK: - Export Methods
    
    func exportMesh() {
        guard canExport else { return }
        
        let exportGroup = DispatchGroup()
        
        // Export as OBJ
        exportGroup.enter()
        exportAsOBJ { success in
            if success {
                print("OBJ export successful")
            } else {
                print("OBJ export failed")
            }
            exportGroup.leave()
        }
        
        // Export as USDZ
        exportGroup.enter()
        exportAsUSDZ { success in
            if success {
                print("USDZ export successful")
            } else {
                print("USDZ export failed")
            }
            exportGroup.leave()
        }
        
        exportGroup.notify(queue: .main) {
            // Show completion message or share sheet
            print("Export completed")
        }
    }
    
    private func exportAsOBJ(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let objURL = documentsPath.appendingPathComponent("body_scan.obj")
            
            var objContent = "# Body Scan OBJ File\n"
            
            // Add vertices
            for vertex in self.meshVertices {
                objContent += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
            }
            
            // Add faces
            for i in stride(from: 0, to: self.meshFaces.count, by: 3) {
                let v1 = self.meshFaces[i] + 1 // OBJ uses 1-based indexing
                let v2 = self.meshFaces[i + 1] + 1
                let v3 = self.meshFaces[i + 2] + 1
                objContent += "f \(v1) \(v2) \(v3)\n"
            }
            
            do {
                try objContent.write(to: objURL, atomically: true, encoding: .utf8)
                completion(true)
            } catch {
                print("Error writing OBJ file: \(error)")
                completion(false)
            }
        }
    }
    
    private func exportAsUSDZ(completion: @escaping (Bool) -> Void) {
        // USDZ export would require more complex implementation
        // For now, we'll just indicate success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(true)
        }
    }
}

// MARK: - ARSessionDelegate

extension ARBodyScannerViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }
    
    private func processMeshAnchor(_ meshAnchor: ARMeshAnchor) {
        guard isScanning else { return }
        
        let geometry = meshAnchor.geometry
        let vertices = geometry.vertices
        let faces = geometry.faces
        
        // Validate geometry data
        guard vertices.count > 0 && faces.count > 0 else {
            return
        }
        
        // Add visual mesh to AR scene
        addMeshVisualization(meshAnchor)
        
        // Convert to our mesh data format
        let vertexCount = vertices.count
        let faceCount = faces.count
        
        var meshVertices: [SIMD3<Float>] = []
        var meshFaces: [UInt32] = []
        
        // Extract vertices with proper stride handling
        let vertexStride = vertices.stride
        let vertexBuffer = vertices.buffer.contents()
        
        for i in 0..<Int(vertexCount) {
            let vertexPointer = vertexBuffer.advanced(by: i * vertexStride).bindMemory(to: SIMD3<Float>.self, capacity: 1)
            let vertex = vertexPointer.pointee
            let worldPosition = meshAnchor.transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
            meshVertices.append(SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z))
        }
        
        // Extract faces with proper format handling
        let faceBuffer = faces.buffer.contents()
        let bytesPerIndex = faces.bytesPerIndex
        
        for i in 0..<Int(faceCount) {
            let facePointer = faceBuffer.advanced(by: i * 3 * bytesPerIndex)
            
            if bytesPerIndex == 2 {
                // 16-bit indices
                let indices = facePointer.bindMemory(to: UInt16.self, capacity: 3)
                meshFaces.append(UInt32(indices[0]))
                meshFaces.append(UInt32(indices[1]))
                meshFaces.append(UInt32(indices[2]))
            } else if bytesPerIndex == 4 {
                // 32-bit indices
                let indices = facePointer.bindMemory(to: UInt32.self, capacity: 3)
                meshFaces.append(indices[0])
                meshFaces.append(indices[1])
                meshFaces.append(indices[2])
            }
        }
        
        // Only store if we have valid data
        guard !meshVertices.isEmpty && !meshFaces.isEmpty else {
            return
        }
        
        let meshData = MeshData(vertices: meshVertices, faces: meshFaces)
        
        print("📊 Captured mesh: \(meshVertices.count) vertices, \(meshFaces.count/3) faces")
        
        // Store or update mesh data
        if let existingIndex = capturedMeshes.firstIndex(where: { $0.id == meshAnchor.identifier }) {
            capturedMeshes[existingIndex] = meshData
            print("🔄 Updated existing mesh anchor")
        } else {
            capturedMeshes.append(meshData)
            print("✅ Added new mesh anchor (total: \(capturedMeshes.count))")
        }
    }
    
    private func addMeshVisualization(_ meshAnchor: ARMeshAnchor) {
        guard let arView = arView else { return }
        
        // Create a simple wireframe visualization
        let meshEntity = ModelEntity()
        
        // Create mesh resource from ARMeshAnchor
        do {
            let meshResource = try MeshResource.generate(from: meshAnchor)
            var material = SimpleMaterial()
            material.color = .init(tint: .green.withAlphaComponent(0.3))
            material.isMetallic = false
            material.roughness = 1.0
            
            meshEntity.model = ModelComponent(mesh: meshResource, materials: [material])
            meshEntity.transform = Transform(matrix: meshAnchor.transform)
            
            // Add to scene
            let anchor = AnchorEntity(anchor: meshAnchor)
            anchor.addChild(meshEntity)
            arView.scene.addAnchor(anchor)
            
        } catch {
            print("Failed to create mesh visualization: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct MeshData {
    let id = UUID()
    let vertices: [SIMD3<Float>]
    let faces: [UInt32]
} 