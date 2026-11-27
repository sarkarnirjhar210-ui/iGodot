from pathlib import Path
import re

# Patch EditorRunBar::play_current_scene to launch an in-editor floating Play window on iOS
patched = False
for p in Path("editor").rglob("editor_run_bar.cpp"):
    text = p.read_text()
    if "IGodotFloatingPlay" in text:
        patched = True
        break

    includes = list(re.finditer(r'^#include\s+[^\n]+\n', text, re.MULTILINE))
    if not includes:
        raise RuntimeError(f"Could not find #include in {p}")
    insert_pos = includes[-1].end()
    extra_headers = """
#ifdef IOS_ENABLED
#include "core/io/resource_loader.h"
#include "core/object/callable_mp.h"
#include "core/object/script_language.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "scene/gui/label.h"
#include "scene/gui/panel_container.h"
#include "scene/gui/subviewport_container.h"
#include "scene/main/viewport.h"
#include "scene/resources/packed_scene.h"
#endif
"""
    text = text[:insert_pos] + extra_headers + text[insert_pos:]

    pattern = re.compile(r'(void\s+EditorRunBar::play_current_scene\s*\([^)]*\)\s*\{)')
    inject = r"""\1
#ifdef IOS_ENABLED
	{
		Node *edited = EditorNode::get_singleton()->get_edited_scene();
		if (edited && !edited->get_scene_file_path().is_empty()) {
			String scene_path = edited->get_scene_file_path();
			Window *root = get_tree()->get_root();
			if (Node *old_win = root->get_node_or_null(NodePath("IGodotFloatingPlay"))) {
				old_win->queue_free();
			}

			PanelContainer *win = memnew(PanelContainer);
			win->set_name("IGodotFloatingPlay");
			Size2i root_size = root->get_size();
			Vector2 win_size = Vector2(root_size.x * 0.80f, root_size.y * 0.80f);
			win->set_size(win_size);
			win->set_position((Vector2(root_size) - win_size) * 0.5f);

			VBoxContainer *vbox = memnew(VBoxContainer);
			win->add_child(vbox);

			HBoxContainer *bar = memnew(HBoxContainer);
			vbox->add_child(bar);

			Label *title = memnew(Label);
			title->set_text("  Floating Play: " + scene_path.get_file());
			title->set_h_size_flags(Control::SIZE_EXPAND_FILL);
			bar->add_child(title);

			Button *close_btn = memnew(Button);
			close_btn->set_text("  Close  ");
			close_btn->connect("pressed", callable_mp((Node *)win, &Node::queue_free));
			bar->add_child(close_btn);

			SubViewportContainer *svc = memnew(SubViewportContainer);
			svc->set_stretch(true);
			svc->set_h_size_flags(Control::SIZE_EXPAND_FILL);
			svc->set_v_size_flags(Control::SIZE_EXPAND_FILL);
			vbox->add_child(svc);

			SubViewport *vp = memnew(SubViewport);
			vp->set_use_own_world_3d(true);
			vp->set_update_mode(SubViewport::UPDATE_ALWAYS);
			vp->set_handle_input_locally(true);
			svc->add_child(vp);

			Ref<PackedScene> packed = ResourceLoader::load(scene_path, "PackedScene", ResourceFormatLoader::CACHE_MODE_IGNORE);
			if (packed.is_valid()) {
				bool prev_scripting = ScriptServer::is_scripting_enabled();
				ScriptServer::set_scripting_enabled(true);
				Node *inst = packed->instantiate();
				ScriptServer::set_scripting_enabled(prev_scripting);
				if (inst) {
					vp->add_child(inst);
				}
			}

			root->add_child(win);
			return;
		}
	}
#endif"""

    new_text, count = pattern.subn(inject, text, count=1)
    if count > 0:
        p.write_text(new_text)
        print(f"Patched in-editor floating Play window in {p}")
        patched = True
        break

if not patched:
    raise RuntimeError("Could not find EditorRunBar::play_current_scene in editor_run_bar.cpp")
