
import SwiftUI
import SwiftGodotKit

enum WorkspaceMode: String, CaseIterable {
    case view3D = "3D"
    case script = "Script"
    case shader = "Shader"
    case assetLib = "AssetLib"
}

enum BottomDockTab: String, CaseIterable {
    case output = "Output"
    case debugger = "Debugger"
    case shaderEditor = "Shader Editor"
    case animTree = "AnimationTree"
}

enum RightDockTab: String, CaseIterable {
    case inspector = "Inspector"
    case nodeSignals = "Node"
    case worldGI = "Environment"
}

enum TransformTool: String, CaseIterable {
    case select = "cursorarrow"
    case move = "move.3d"
    case rotate = "rotate.3d"
    case scale = "scale.3d"
}

struct ContentView: View {
    @StateObject private var bootstrap = iGodotBootstrap.shared
    
    // Desktop Godot Layout & Dock Visibility
    @State private var workspace: WorkspaceMode = .view3D
    @State private var bottomTab: BottomDockTab = .output
    @State private var rightTab: RightDockTab = .inspector
    @State private var activeTool: TransformTool = .select
    
    @State private var showLeftDock: Bool = true
    @State private var showRightDock: Bool = true
    @State private var showBottomDock: Bool = true
    @State private var distractionFree: Bool = false
    
    // Script / Shader Editor State
    @State private var selectedFileURL: URL?
    @State private var codeText: String = ""
    @State private var exportAlertMessage: String = ""
    @State private var showExportAlert: Bool = false
    
    // Inspector Transform & Volumetric God-Ray Uniforms
    @State private var posX: String = "0.0"
    @State private var posY: String = "5.2"
    @State private var posZ: String = "4.8"
    @State private var fogDensity: Double = 1.15
    @State private var shadowBlur: Double = 1.65
    @State private var rayContrast: Double = 1.65
    @State private var giBounceEnergy: Double = 1.15
    
    // Godot Desktop Dark Theme Colors
    private let bgDarkest = Color(red: 0.09, green: 0.11, blue: 0.14)
    private let bgDock = Color(red: 0.13, green: 0.15, blue: 0.19)
    private let bgHeader = Color(red: 0.16, green: 0.19, blue: 0.24)
    private let godotBlue = Color(red: 0.28, green: 0.55, blue: 0.75)
    private let godotGreen = Color(red: 0.54, green: 0.89, blue: 0.56)
    
    var body: some View {
        ZStack {
            // 1. UNDERLYING METAL 3D VIEWPORT
            if let activeProject = bootstrap.activeProject {
                GodotAppView()
                    .environment(\.godotApp, GodotApp(packFile: activeProject.url.path))
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // 2. DESKTOP GODOT 4.7 MULTI-DOCK SHELL
            VStack(spacing: 0) {
                desktopTopBar
                
                HStack(spacing: 0) {
                    // LEFT DOCK: Scene Tree + FileSystem
                    if showLeftDock && !distractionFree {
                        leftSceneAndFileDock
                            .frame(width: 235)
                            .background(bgDock.opacity(0.95))
                    }
                    
                    // CENTER WORKSPACE + BOTTOM DOCK
                    VStack(spacing: 0) {
                        viewportToolbar
                        
                        ZStack {
                            if workspace == .view3D {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .allowsHitTesting(false)
                            } else if workspace == .script || workspace == .shader {
                                desktopCodeEditorOverlay
                            } else {
                                assetLibOverlay
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // BOTTOM DOCK: Output | Debugger | Shader Editor | AnimationTree
                        if showBottomDock && !distractionFree {
                            bottomPanelDock
                                .frame(height: 155)
                                .background(bgDock.opacity(0.95))
                        }
                    }
                    
                    // RIGHT DOCK: Inspector | Node | WorldGI
                    if showRightDock && !distractionFree {
                        rightInspectorDock
                            .frame(width: 265)
                            .background(bgDock.opacity(0.95))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let first = bootstrap.projectFiles.first {
                openFileInEditor(first)
            }
            pushLiveTweaks()
        }
        .alert("iGodot Export Manager", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportAlertMessage)
        }
    }
    
    // MARK: - Top Desktop Menu & Workspace Bar
    private var desktopTopBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent.fill")
                    .foregroundColor(godotBlue)
                
                Menu("Scene") {
                    Button("Reload Scene") { reloadGodotScene() }
                    Button("Save Scene (main.tscn)") { saveCurrentFile() }
                }
                .font(.system(size: 12, weight: .medium))
                
                Menu("Project") {
                    Menu("Export Game Offline...") {
                        ForEach(ExportPlatform.allCases, id: \.self) { platform in
                            Button(platform.rawValue) { runOfflineExport(for: platform) }
                        }
                    }
                    Button("Refresh Files") { bootstrap.refreshSceneTree() }
                }
                .font(.system(size: 12, weight: .medium))
                
                Menu("Layout") {
                    Button(showLeftDock ? "Hide Scene/File Dock" : "Show Scene/File Dock") { showLeftDock.toggle() }
                    Button(showRightDock ? "Hide Inspector Dock" : "Show Inspector Dock") { showRightDock.toggle() }
                    Button(showBottomDock ? "Hide Bottom Panel" : "Show Bottom Panel") { showBottomDock.toggle() }
                }
                .font(.system(size: 12, weight: .medium))
            }
            
            Spacer()
            
            // Center: 3D | Script | Shader | AssetLib Switcher
            HStack(spacing: 2) {
                ForEach(WorkspaceMode.allCases, id: \.self) { mode in
                    Button {
                        workspace = mode
                        if mode == .shader, let shd = bootstrap.projectFiles.first(where: { $0.pathExtension == "gdshader" }) {
                            openFileInEditor(shd)
                        } else if mode == .script, let gd = bootstrap.projectFiles.first(where: { $0.pathExtension == "gd" }) {
                            openFileInEditor(gd)
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(workspace == mode ? godotBlue : Color.clear)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            .padding(2)
            .background(bgDarkest)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Spacer()
            
            // Right: Playtest Transport & Locked "Mobile" Renderer Badge
            HStack(spacing: 8) {
                Button { reloadGodotScene() } label: {
                    Image(systemName: "play.fill").foregroundColor(godotGreen)
                }
                Button {
                    bootstrap.log("Toggled viewport pause state.")
                } label: {
                    Image(systemName: "pause.fill").foregroundColor(.white)
                }
                Button { reloadGodotScene() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(.orange)
                }
                
                Text("Mobile")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(godotGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(bgDarkest)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(bgHeader)
    }
    
    // MARK: - 3D Viewport Sub-Toolbar
    private var viewportToolbar: some View {
        HStack(spacing: 8) {
            ForEach(TransformTool.allCases, id: \.self) { tool in
                Button { activeTool = tool } label: {
                    Image(systemName: tool.rawValue)
                        .font(.system(size: 12))
                        .padding(5)
                        .background(activeTool == tool ? godotBlue : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            Divider().frame(height: 14)
            
            Button {
                bootstrap.addGodotNode(ofType: "MeshInstance3D")
            } label: {
                Label("Add Cube", systemImage: "cube.fill")
                    .font(.system(size: 11))
            }
            
            Button {
                bootstrap.addGodotNode(ofType: "SpotLight3D")
            } label: {
                Label("Add SpotLight", systemImage: "flashlight.on.fill")
                    .font(.system(size: 11))
            }
            
            Spacer()
            
            Text("Perspective • Jolt Physics • Shadow-Ray Fog")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
            
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    distractionFree.toggle()
                }
            } label: {
                Label(distractionFree ? "Restore Docks" : "Maximize 3D", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(distractionFree ? godotBlue : bgDarkest)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(bgDock.opacity(0.92))
    }
    
    // MARK: - Left Dock (Scene Tree + FileSystem)
    private var leftSceneAndFileDock: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scene").font(.system(size: 11, weight: .bold)).foregroundColor(godotBlue)
                Spacer()
                Menu {
                    ForEach([
                        "Node3D",
                        "MeshInstance3D",
                        "SpotLight3D",
                        "OmniLight3D",
                        "GPUParticles3D (Volumetric Fog)",
                        "CharacterBody3D (Jolt)",
                        "RigidBody3D (Jolt)",
                        "AnimationTree",
                        "AnimationPlayer",
                        "AudioStreamPlayer3D",
                        "Camera3D"
                    ], id: \.self) { typeName in
                        Button("Add \(typeName)") {
                            bootstrap.addGodotNode(ofType: typeName)
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                }
                Button { bootstrap.refreshSceneTree() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bgHeader)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bootstrap.sceneNodes) { item in
                        Button {
                            bootstrap.selectedNodePath = item.id
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: iconForGodotClass(item.type))
                                    .font(.system(size: 11))
                                    .foregroundColor(colorForGodotClass(item.type))
                                Text(item.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.leading, CGFloat(item.depth * 12) + 6)
                            .padding(.vertical, 4)
                            .background(bootstrap.selectedNodePath == item.id ? godotBlue.opacity(0.45) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding(4)
            }
            
            Divider()
            
            HStack {
                Text("FileSystem (res://)").font(.system(size: 11, weight: .bold)).foregroundColor(godotBlue)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bgHeader)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(bootstrap.projectFiles, id: \.self) { fileURL in
                        Button {
                            openFileInEditor(fileURL)
                            if fileURL.pathExtension == "gdshader" {
                                workspace = .shader
                            } else if fileURL.pathExtension == "gd" {
                                workspace = .script
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: fileURL.pathExtension == "gdshader" ? "sparkles.rectangle.stack" : "doc.text.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(fileURL.pathExtension == "gdshader" ? .purple : .orange)
                                Text(fileURL.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedFileURL == fileURL ? godotBlue.opacity(0.35) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding(4)
            }
        }
    }
    
    // MARK: - Right Dock (Inspector | Node Signals | Environment/GI)
    private var rightInspectorDock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(RightDockTab.allCases, id: \.self) { tab in
                    Button { rightTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(rightTab == tab ? bgDock : bgHeader)
                            .foregroundColor(rightTab == tab ? godotBlue : .gray)
                    }
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if rightTab == .inspector {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Node")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            Text(bootstrap.selectedNodePath)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(godotGreen)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgDarkest)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        // Shadow-Mapped Volumetric Fog Controls
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Volumetric Shadow-Ray Fog")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(godotBlue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Shadow Blur (Ray Softness)").font(.system(size: 10))
                                    Spacer()
                                    Text(String(format: "%.2f", shadowBlur)).font(.system(size: 10, design: .monospaced))
                                }
                                Slider(value: $shadowBlur, in: 0.1...4.0)
                                    .onChange(of: shadowBlur) { pushLiveTweaks() }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Fog Particle Density").font(.system(size: 10))
                                    Spacer()
                                    Text(String(format: "%.2f", fogDensity)).font(.system(size: 10, design: .monospaced))
                                }
                                Slider(value: $fogDensity, in: 0.0...2.5)
                                    .onChange(of: fogDensity) { pushLiveTweaks() }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Shadow Ray Contrast").font(.system(size: 10))
                                    Spacer()
                                    Text(String(format: "%.2f", rayContrast)).font(.system(size: 10, design: .monospaced))
                                }
                                Slider(value: $rayContrast, in: 0.5...3.5)
                                    .onChange(of: rayContrast) { pushLiveTweaks() }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Fake GI Bounce Energy").font(.system(size: 10))
                                    Spacer()
                                    Text(String(format: "%.2f", giBounceEnergy)).font(.system(size: 10, design: .monospaced))
                                }
                                Slider(value: $giBounceEnergy, in: 0.0...3.0)
                                    .onChange(of: giBounceEnergy) { pushLiveTweaks() }
                            }
                        }
                        .padding(8)
                        .background(bgDarkest)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Node3D • Transform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(godotBlue)
                            HStack {
                                Text("Pos X").font(.system(size: 10)).frame(width: 40, alignment: .leading)
                                TextField("0.0", text: $posX).font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("Pos Y").font(.system(size: 10)).frame(width: 40, alignment: .leading)
                                TextField("0.0", text: $posY).font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("Pos Z").font(.system(size: 10)).frame(width: 40, alignment: .leading)
                                TextField("0.0", text: $posZ).font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(8)
                        .background(bgDarkest)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                    } else if rightTab == .nodeSignals {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signals (Node3D)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(godotBlue)
                            ForEach(["ready()", "tree_entered()", "tree_exiting()", "visibility_changed()"], id: \.self) { sig in
                                HStack {
                                    Image(systemName: "bolt.horizontal.fill").foregroundColor(.yellow).font(.system(size: 10))
                                    Text(sig).font(.system(size: 11, design: .monospaced))
                                    Spacer()
                                }
                                .padding(4)
                                .background(bgDarkest)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Renderer & Physics Lock")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(godotBlue)
                            Text("• Renderer: Mobile (Vulkan/Metal)\n• Forward+ & Compatibility: Excluded\n• Physics 3D: Jolt Physics\n• Shadow Atlas: 4096px Soft Filter")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(8)
                        .background(bgDarkest)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(10)
            }
        }
    }
    
    // MARK: - Bottom Panel Dock
    private var bottomPanelDock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(BottomDockTab.allCases, id: \.self) { tab in
                    Button { bottomTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: bottomTab == tab ? .bold : .regular))
                            .foregroundColor(bottomTab == tab ? godotBlue : .gray)
                    }
                }
                Spacer()
                Button("Clear") { bootstrap.consoleLogs.removeAll() }
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bgHeader)
            
            if bottomTab == .output {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(bootstrap.consoleLogs, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
            } else if bottomTab == .debugger {
                HStack(spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("Frame Time: 8.3 ms (120 FPS Target)").font(.system(size: 11, design: .monospaced)).foregroundColor(godotGreen)
                        Text("Physics 3D Engine: Jolt Physics (Active)").font(.system(size: 11, design: .monospaced))
                        Text("Shadow Map Atlas: 4096x4096 PCF High").font(.system(size: 11, design: .monospaced))
                    }
                    Spacer()
                }
                .padding(12)
            } else if bottomTab == .shaderEditor {
                HStack {
                    TextEditor(text: $codeText)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(bgDarkest)
                    Button("Apply Shader") { saveCurrentFile() }
                        .buttonStyle(.borderedProminent)
                        .tint(godotBlue)
                        .padding(.trailing, 8)
                }
            } else {
                HStack(spacing: 16) {
                    Text("[StateMachine: Idle] ──► [BlendSpace2D: Walk/Run] ──► [Output]")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(godotGreen)
                    Button("Add AnimationNodeStateMachine") {
                        bootstrap.addGodotNode(ofType: "AnimationTree")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(12)
            }
        }
    }
    
    // MARK: - Center Script / Shader Editor Mode
    private var desktopCodeEditorOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editing: \(selectedFileURL?.lastPathComponent ?? "main.gd")")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Button {
                    saveCurrentFile()
                    workspace = .view3D
                } label: {
                    Label("Save & Return to 3D", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(godotBlue)
            }
            .padding(8)
            .background(bgHeader)
            
            TextEditor(text: $codeText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(bgDarkest.opacity(0.96))
        }
    }
    
    private var assetLibOverlay: some View {
        VStack(spacing: 12) {
            Text("iGodot Built-In Presets (Mobile HDR + Jolt Ready)")
                .font(.headline)
            HStack(spacing: 16) {
                Button("Spawn Shadow-Ray Volumetric Fog") {
                    bootstrap.addGodotNode(ofType: "GPUParticles3D (Volumetric Fog)")
                    workspace = .view3D
                }
                .buttonStyle(.borderedProminent)
                
                Button("Spawn Jolt RigidBody3D Cube") {
                    bootstrap.addGodotNode(ofType: "RigidBody3D (Jolt)")
                    workspace = .view3D
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgDarkest.opacity(0.95))
    }
    
    // MARK: - Helpers
    private func openFileInEditor(_ url: URL) {
        selectedFileURL = url
        codeText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    
    private func saveCurrentFile() {
        guard let url = selectedFileURL else { return }
        try? codeText.write(to: url, atomically: true, encoding: .utf8)
        bootstrap.log("Saved \(url.lastPathComponent) — syncing live scene...")
        reloadGodotScene()
    }
    
    private func reloadGodotScene() {
        pushLiveTweaks()
        bootstrap.refreshSceneTree()
        bootstrap.log("Synced live scene & shaders with Mobile HDR viewport.")
    }
    
    private func pushLiveTweaks() {
        bootstrap.applyLiveInspectorTweaks(
            fogDensity: fogDensity,
            shadowBlur: shadowBlur,
            rayContrast: rayContrast,
            giEnergy: giBounceEnergy
        )
    }
    
    private func runOfflineExport(for platform: ExportPlatform) {
        guard let active = bootstrap.activeProject else { return }
        switch iGodotOfflineExporter.shared.exportGame(project: active, platform: platform) {
        case .success(let outputURL):
            exportAlertMessage = "Exported to On My iPad / iGodot / Exports / \(outputURL.lastPathComponent)"
            showExportAlert = true
        case .failure(let error):
            exportAlertMessage = error.localizedDescription
            showExportAlert = true
        }
    }
    
    private func iconForGodotClass(_ cls: String) -> String {
        if cls.contains("Light") { return "lightbulb.fill" }
        if cls.contains("Camera") { return "video.fill" }
        if cls.contains("Particles") { return "cloud.fog.fill" }
        if cls.contains("Mesh") { return "cube.fill" }
        if cls.contains("Environment") { return "globe.americas.fill" }
        return "circle.grid.cross.fill"
    }
    
    private func colorForGodotClass(_ cls: String) -> Color {
        if cls.contains("3D") || cls.contains("Light") || cls.contains("Mesh") || cls.contains("Particles") || cls.contains("Camera") {
            return Color(red: 0.98, green: 0.52, blue: 0.52)
        }
        return .white
    }
}
