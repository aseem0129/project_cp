//
//  ARBodyScannerView.swift
//  counterpart_jul15
//
//  Created by Aseem Sethi on 7/15/25.
//

import SwiftUI
import ARKit
import RealityKit
import MetalKit

struct ARBodyScannerView: View {
    @StateObject private var scannerViewModel = ARBodyScannerViewModel()
    @State private var showingInstructions = true
    @State private var scanningPhase: ScanningPhase = .preparation
    
    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(viewModel: scannerViewModel)
                .ignoresSafeArea()
            
            // UI Overlay
            VStack {
                // Top status bar
                HStack {
                    Button("Cancel") {
                        scannerViewModel.cancelScanning()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Text(scanningPhase.displayText)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                    
                    Spacer()
                    
                    Button("Reset") {
                        scannerViewModel.resetScanning()
                    }
                    .foregroundColor(.white)
                    .padding()
                }
                .background(Color.black.opacity(0.7))
                
                Spacer()
                
                // Instructions panel
                if showingInstructions {
                    InstructionsPanel(
                        phase: scanningPhase,
                        onDismiss: { showingInstructions = false }
                    )
                    .padding()
                }
                
                // Bottom controls
                HStack {
                    // Scan progress indicator
                    VStack {
                        Text("Scan Progress")
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        ProgressView(value: scannerViewModel.scanProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 120)
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Main scan button
                    Button(action: {
                        if scannerViewModel.isScanning {
                            scannerViewModel.pauseScanning()
                        } else {
                            scannerViewModel.startScanning()
                        }
                    }) {
                        Image(systemName: scannerViewModel.isScanning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(scannerViewModel.isScanning ? .orange : .green)
                    }
                    
                    Spacer()
                    
                    // Export button
                    Button("Export") {
                        scannerViewModel.exportMesh()
                    }
                    .disabled(!scannerViewModel.canExport)
                    .padding()
                    .background(scannerViewModel.canExport ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.black.opacity(0.7))
            }
        }
        .onReceive(scannerViewModel.$currentPhase) { phase in
            scanningPhase = phase
        }
        .onAppear {
            scannerViewModel.setupAR()
        }
    }
}

// MARK: - Supporting Views

struct InstructionsPanel: View {
    let phase: ScanningPhase
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scanning Instructions")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("×") {
                    onDismiss()
                }
                .font(.title2)
                .foregroundColor(.white)
            }
            
            Text(phase.instructions)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            if !phase.tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tips:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                    
                    ForEach(phase.tips, id: \.self) { tip in
                        Text("• \(tip)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
}

// MARK: - ARViewContainer

struct ARViewContainer: UIViewRepresentable {
    let viewModel: ARBodyScannerViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupARView(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates handled by view model
    }
}

// MARK: - Scanning Phases

enum ScanningPhase: CaseIterable {
    case preparation
    case frontScan
    case sideScan
    case backScan
    case processing
    case complete
    
    var displayText: String {
        switch self {
        case .preparation: return "Prepare to Scan"
        case .frontScan: return "Front Scan"
        case .sideScan: return "Side Scan"
        case .backScan: return "Back Scan"
        case .processing: return "Processing..."
        case .complete: return "Scan Complete"
        }
    }
    
    var instructions: String {
        switch self {
        case .preparation:
            return "Position yourself 6 feet away from the camera. Stand straight with arms slightly away from your body. Make sure you're in a well-lit area with minimal background objects."
        case .frontScan:
            return "Hold your phone at chest height and slowly move it up and down while walking around your front side. Keep the phone pointed at your body."
        case .sideScan:
            return "Move to capture your side profile. Walk slowly around your side while keeping the phone pointed at your body."
        case .backScan:
            return "Continue around to capture your back. Move slowly and maintain consistent distance from your body."
        case .processing:
            return "Processing your scan data. This may take a few moments..."
        case .complete:
            return "Scan completed successfully! You can now export your 3D mesh."
        }
    }
    
    var tips: [String] {
        switch self {
        case .preparation:
            return [
                "Wear form-fitting clothes for best results",
                "Ensure good lighting",
                "Remove any loose accessories"
            ]
        case .frontScan, .sideScan, .backScan:
            return [
                "Move slowly and steadily",
                "Keep consistent distance",
                "Overlap your scanning paths"
            ]
        case .processing:
            return ["Please wait while we process your scan"]
        case .complete:
            return ["Your 3D mesh is ready for export"]
        }
    }
}

#Preview {
    ARBodyScannerView()
} 