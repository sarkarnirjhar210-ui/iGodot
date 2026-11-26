import Foundation

struct iGodotProject: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
}

struct SceneNodeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let depth: Int
}

final class iGodotBootstrap: ObservableObject {
    static let shared = iGodotBootstrap()
    
    @Published var projects: [iGodotProject] = []
    @Published var activeProject: iGodotProject?
    @Published var projectFiles: [URL] = []
    @Published var sceneNodes: [SceneNodeItem] = [
        SceneNodeItem(id: "/root/Main3D", name: "Main3D", type: "Node3D", depth: 0),
        SceneNodeItem(id: "/root/Main3D/WorldEnvironment", name: "WorldEnvironment", type: "WorldEnvironment", depth: 1),
        SceneNodeItem(id: "/root/Main3D/Camera3D", name: "Camera3D", type: "Camera3D", depth: 1),
        SceneNodeItem(id: "/root/Main3D/SpotLight3D", name: "SpotLight3D", type: "SpotLight3D", depth: 1),
        SceneNodeItem(id: "/root/Main3D/FakeGI_BounceOmni", name: "FakeGI_BounceOmni", type: "OmniLight3D", depth: 1),
        SceneNodeItem(id: "/root/Main3D/ShadowMappedVolumetricFog", name: "ShadowMappedVolumetricFog", type: "GPUParticles3D", depth: 1),
        SceneNodeItem(id: "/root/Main3D/ShadowCasterPillars", name: "ShadowCasterPillars", type: "Node3D", depth: 1)
    ]
    @Published var selectedNodePath: String = "/root/Main3D/ShadowMappedVolumetricFog"
    @Published var consoleLogs: [String] = [
        "[iGodot 4.7] Engine initialized (Renderer: Mobile HDR | Physics: Jolt 3D)",
        "[iGodot 4.7] Compatibility & Forward+ renderers stripped and locked out.",
        "[VolumetricFog] Shadow-mapped particle god-rays active (High Shadow Filter)."
    ]
    
    private var spawnedNodesQueue: [String] = []
    let fm = FileManager.default
    
    var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var projectsRootURL: URL {
        documentsURL.appendingPathComponent("Projects", isDirectory: true)
    }
    
    var templatesRootURL: URL {
        documentsURL.appendingPathComponent("Templates", isDirectory: true)
    }
    
    init() {
        setupDirectories()
        refreshProjects()
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        consoleLogs.append("[\(formatter.string(from: Date()))] \(message)")
    }
    
    func setupDirectories() {
        try? fm.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: templatesRootURL, withIntermediateDirectories: true)
        createNewProject(named: "MoodyShowcase")
    }
    
    func refreshProjects() {
        guard let contents = try? fm.contentsOfDirectory(at: projectsRootURL, includingPropertiesForKeys: nil) else { return }
        projects = contents.compactMap { url in
            let godotFile = url.appendingPathComponent("project.godot")
            guard fm.fileExists(atPath: godotFile.path) else { return nil }
            return iGodotProject(name: url.lastPathComponent, url: url)
        }
        if activeProject == nil {
            activeProject = projects.first
            if let active = activeProject {
                loadProjectFiles(for: active)
            }
        }
    }
    
    func loadProjectFiles(for project: iGodotProject) {
        var found: [URL] = []
        if let enumerator = fm.enumerator(at: project.url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                if ["gd", "gdshader", "tscn", "godot"].contains(ext) {
                    found.append(fileURL)
                }
            }
        }
        projectFiles = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    func refreshSceneTree() {
        if let active = activeProject {
            loadProjectFiles(for: active)
        }
    }
    
    func addGodotNode(ofType typeName: String) {
        let cleanType = typeName.components(separatedBy: " ").first ?? "Node3D"
        let nodeName = "\(cleanType)_\(Int.random(in: 10...99))"
        let newPath = "/root/Main3D/\(nodeName)"
        sceneNodes.append(SceneNodeItem(id: newPath, name: nodeName, type: cleanType, depth: 1))
        selectedNodePath = newPath
        spawnedNodesQueue.append("\(cleanType):\(nodeName)")
        applyLiveInspectorTweaks(fogDensity: 1.15, shadowBlur: 1.65, rayContrast: 1.65, giEnergy: 1.15)
        log("Added node: \(nodeName) (\(typeName))")
    }
    
    func applyLiveInspectorTweaks(
        fogDensity: Double,
        shadowBlur: Double,
        rayContrast: Double,
        giEnergy: Double
    ) {
        guard let active = activeProject else { return }
        let liveFile = active.url.appendingPathComponent("igodot_live.json")
        let payload: [String: Any] = [
            "fog_density": fogDensity,
            "shadow_blur": shadowBlur,
            "ray_contrast": rayContrast,
            "gi_energy": giEnergy,
            "spawn_queue": spawnedNodesQueue
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            try? data.write(to: liveFile, options: .atomic)
        }
    }
    
    func createNewProject(named name: String) {
        let projURL = projectsRootURL.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: projURL, withIntermediateDirectories: true)
        
        // 1. project.godot (Strictly locked to Mobile HDR + Jolt Physics + High Soft Shadows)
        let projectGodot = """
        ; Engine configuration file.
        ; iGodot 4.7 Desktop-Compatible Project (Locked to Mobile Renderer)
        config_version=5
        
        [application]
        config/name="\(name)"
        run/main_scene="res://main.tscn"
        config/features=PackedStringArray("4.7", "Mobile")
        
        [physics]
        3d/physics_engine="Jolt Physics"
        
        [rendering]
        renderer/rendering_method="mobile"
        lights_and_shadows/positional_shadow/atlas_size=4096
        lights_and_shadows/positional_shadow/soft_shadow_filter_quality=3
        anti_aliasing/quality/msaa_3d=2
        """
        try? projectGodot.write(to: projURL.appendingPathComponent("project.godot"), atomically: true, encoding: .utf8)
        
        // 2. Shadow-Mapped Volumetric Fog Shader (volumetric_fog.gdshader)
        let volShader = """
        shader_type spatial;
        render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;
        
        uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
        uniform vec4 fog_tint : source_color = vec4(0.95, 0.86, 0.74, 0.12);
        uniform float proximity_fade : hint_range(0.1, 4.0) = 1.35;
        uniform float shadow_ray_contrast : hint_range(0.5, 4.0) = 1.65;
        uniform float fog_density : hint_range(0.0, 3.0) = 1.15;
        
        varying vec3 v_world_pos;
        
        float hash(vec3 p) {
            p = fract(p * 0.3183099 + 0.1);
            p *= 17.0;
            return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
        }
        
        float noise3d(vec3 x) {
            vec3 i = floor(x);
            vec3 f = fract(x);
            f = f * f * (3.0 - 2.0 * f);
            return mix(
                mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
                    mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
                mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                    mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
                f.z);
        }
        
        void vertex() {
            MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
                INV_VIEW_MATRIX[0],
                INV_VIEW_MATRIX[1],
                INV_VIEW_MATRIX[2],
                MODEL_MATRIX[3]
            );
            v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        }
        
        void fragment() {
            vec2 centered_uv = UV * 2.0 - 1.0;
            float dist = dot(centered_uv, centered_uv);
            float radial_mask = pow(clamp(1.0 - dist, 0.0, 1.0), 2.2);
        
            vec3 n_pos = v_world_pos * 0.65 + vec3(TIME * 0.14, -TIME * 0.08, TIME * 0.1);
            float wisp = noise3d(n_pos) * 0.65 + noise3d(n_pos * 2.3) * 0.35;
        
            float raw_depth = texture(depth_texture, SCREEN_UV).r;
            vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
            vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
            view_pos /= view_pos.w;
            float depth_diff = VERTEX.z - view_pos.z;
            float depth_fade = clamp(depth_diff / proximity_fade, 0.0, 1.0);
            float cam_fade = smoothstep(0.4, 2.2, -VERTEX.z);
        
            ALBEDO = fog_tint.rgb;
            ALPHA = radial_mask * wisp * fog_tint.a * fog_density * depth_fade * cam_fade;
        }
        
        void light() {
            // Real-time Shadow Map God-Rays (ATTENUATION carves shafts behind shadow casters)
            vec3 shadow_ray = pow(ATTENUATION, vec3(shadow_ray_contrast));
            float phase = mix(0.65, 1.65, clamp(dot(VIEW, -LIGHT), 0.0, 1.0));
            DIFFUSE_LIGHT += LIGHT_COLOR * shadow_ray * phase * 0.45;
        }
        """
        try? volShader.write(to: projURL.appendingPathComponent("volumetric_fog.gdshader"), atomically: true, encoding: .utf8)
        
        // 3. Main Scene Script (main.gd) - Builds the Shadow-Mapped Particle God-Ray Showcase & reads live Inspector tweaks
        let mainGD = """
        extends Node3D
        
        var time_acc: float = 0.0
        var sync_timer: float = 0.0
        var spot: SpotLight3D
        var bounce_omni: OmniLight3D
        var fog_mat: ShaderMaterial
        var spawned_names: Dictionary = {}
        
        func _ready() -> void:
            _build_volumetric_showcase()
        
        func _build_volumetric_showcase() -> void:
            var floor_mesh := MeshInstance3D.new()
            floor_mesh.name = "Floor"
            var plane := PlaneMesh.new()
            plane.size = Vector2(28, 28)
            floor_mesh.mesh = plane
            var floor_mat := StandardMaterial3D.new()
            floor_mat.albedo_color = Color(0.08, 0.08, 0.09)
            floor_mat.roughness = 0.85
            floor_mesh.material_override = floor_mat
            add_child(floor_mesh)
        
            var shadow_bars := Node3D.new()
            shadow_bars.name = "ShadowCasterPillars"
            add_child(shadow_bars)
        
            var pillar_mat := StandardMaterial3D.new()
            pillar_mat.albedo_color = Color(0.1, 0.11, 0.13)
            pillar_mat.roughness = 0.9
        
            for i in range(-2, 3):
                var pillar := MeshInstance3D.new()
                pillar.name = "Pillar_" + str(i + 3)
                var box := BoxMesh.new()
                box.size = Vector3(0.42, 5.0, 0.42)
                pillar.mesh = box
                pillar.material_override = pillar_mat
                pillar.position = Vector3(float(i) * 1.15, 2.5, 1.2)
                shadow_bars.add_child(pillar)
        
            spot = get_node_or_null("SpotLight3D")
            if spot:
                spot.position = Vector3(0, 5.2, 4.8)
                spot.look_at_from_position(spot.position, Vector3(0, 0.8, -1.5), Vector3.UP)
                spot.shadow_enabled = true
                spot.shadow_blur = 1.65
                spot.light_energy = 7.5
                spot.spot_range = 22.0
                spot.spot_angle = 42.0
        
            bounce_omni = OmniLight3D.new()
            bounce_omni.name = "FakeGI_BounceOmni"
            bounce_omni.position = Vector3(0, 1.2, -1.0)
            bounce_omni.light_color = Color(0.95, 0.78, 0.58)
            bounce_omni.light_energy = 1.15
            bounce_omni.omni_range = 9.5
            bounce_omni.shadow_enabled = false
            add_child(bounce_omni)
        
            var fog_particles := GPUParticles3D.new()
            fog_particles.name = "ShadowMappedVolumetricFog"
            fog_particles.amount = 220
            fog_particles.lifetime = 8.0
            fog_particles.preprocess = 8.0
            fog_particles.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 10, 20))
            fog_particles.position = Vector3(0, 2.2, -0.5)
        
            var proc := ParticleProcessMaterial.new()
            proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
            proc.emission_box_extents = Vector3(4.5, 2.4, 4.5)
            proc.gravity = Vector3(0.0, 0.04, 0.0)
            proc.initial_velocity_min = 0.05
            proc.initial_velocity_max = 0.18
            proc.direction = Vector3(1, 0.2, 0.5)
            proc.spread = 180.0
            fog_particles.process_material = proc
        
            var quad := QuadMesh.new()
            quad.size = Vector2(3.6, 3.6)
            fog_mat = ShaderMaterial.new()
            fog_mat.shader = load("res://volumetric_fog.gdshader")
            quad.material = fog_mat
            fog_particles.draw_pass_1 = quad
            add_child(fog_particles)
        
        func _process(delta: float) -> void:
            time_acc += delta
            sync_timer += delta
            if spot:
                spot.position.x = sin(time_acc * 0.55) * 2.4
                spot.look_at(Vector3(0, 0.5, -1.5), Vector3.UP)
            if sync_timer > 0.15:
                sync_timer = 0.0
                _poll_inspector_bridge()
        
        func _poll_inspector_bridge() -> void:
            if not FileAccess.file_exists("res://igodot_live.json"):
                return
            var f := FileAccess.open("res://igodot_live.json", FileAccess.READ)
            if not f:
                return
            var data = JSON.parse_string(f.get_as_text())
            if typeof(data) != TYPE_DICTIONARY:
                return
            if spot and data.has("shadow_blur"):
                spot.shadow_blur = float(data["shadow_blur"])
            if bounce_omni and data.has("gi_energy"):
                bounce_omni.light_energy = float(data["gi_energy"])
            if fog_mat:
                if data.has("fog_density"):
                    fog_mat.set_shader_parameter("fog_density", float(data["fog_density"]))
                if data.has("ray_contrast"):
                    fog_mat.set_shader_parameter("shadow_ray_contrast", float(data["ray_contrast"]))
            if data.has("spawn_queue"):
                for entry in data["spawn_queue"]:
                    var parts: PackedStringArray = String(entry).split(":")
                    if parts.size() == 2 and not spawned_names.has(parts[1]):
                        spawned_names[parts[1]] = true
                        _spawn_dynamic_node(parts[0], parts[1])
        
        func _spawn_dynamic_node(type_str: String, node_name: String) -> void:
            var n: Node3D
            if type_str == "MeshInstance3D":
                var m := MeshInstance3D.new()
                m.mesh = BoxMesh.new()
                n = m
            elif type_str == "SpotLight3D":
                var s := SpotLight3D.new()
                s.shadow_enabled = true
                s.light_energy = 5.0
                n = s
            else:
                n = Node3D.new()
            n.name = node_name
            n.position = Vector3(randf_range(-2.0, 2.0), 1.5, randf_range(-1.0, 1.5))
            add_child(n)
        """
        try? mainGD.write(to: projURL.appendingPathComponent("main.gd"), atomically: true, encoding: .utf8)
        
        // 4. Clean main.tscn
        let mainTSCN = """
        [gd_scene load_steps=3 format=3 uid="uid://igodot_main"]
        
        [ext_resource type="Script" path="res://main.gd" id="1_main"]
        
        [sub_resource type="Environment" id="Env_1"]
        background_mode = 1
        background_color = Color(0.02, 0.025, 0.035, 1)
        ambient_light_source = 2
        ambient_light_color = Color(0.07, 0.09, 0.12, 1)
        tonemap_mode = 3
        glow_enabled = true
        glow_intensity = 0.55
        glow_bloom = 0.15
        
        [node name="Main3D" type="Node3D"]
        script = ExtResource("1_main")
        
        [node name="WorldEnvironment" type="WorldEnvironment" parent="."]
        environment = SubResource("Env_1")
        
        [node name="Camera3D" type="Camera3D" parent="."]
        transform = Transform3D(0.906, -0.088, 0.413, 0, 0.978, 0.208, -0.422, -0.188, 0.886, 3.8, 2.7, 6.2)
        current = true
        
        [node name="SpotLight3D" type="SpotLight3D" parent="."]
        transform = Transform3D(1, 0, 0, 0, 0.707, 0.707, 0, -0.707, 0.707, 0, 5.2, 4.8)
        light_color = Color(0.98, 0.86, 0.70, 1)
        light_energy = 7.5
        shadow_enabled = true
        shadow_blur = 1.65
        spot_range = 22.0
        spot_angle = 42.0
        """
        try? mainTSCN.write(to: projURL.appendingPathComponent("main.tscn"), atomically: true, encoding: .utf8)
        
        refreshProjects()
    }
}
