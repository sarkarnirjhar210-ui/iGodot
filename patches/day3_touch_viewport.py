from pathlib import Path
import re

# 1. Silence "Mouse is not supported by this display server." spam on iOS
for ds_cpp in [Path("servers/display/display_server.cpp"), Path("servers/display_server.cpp")]:
    if ds_cpp.exists():
        text = ds_cpp.read_text()
        if "Mouse is not supported by this display server." in text:
            patched = re.sub(
                r'([ \t]*WARN_PRINT[^\n]*"Mouse is not supported by this display server\."[^\n]*\n)',
                r'#ifndef IOS_ENABLED\n\1#endif\n',
                text,
            )
            if patched != text:
                ds_cpp.write_text(patched)
                print(f"Silenced iOS mouse warning spam in {ds_cpp}")
        break

# 2. Add Xogot-style 1-finger orbit + 2-finger pan & pinch-zoom to 3D viewport
patched_3d = False
for p in Path("editor").rglob("node_3d_editor_plugin.cpp"):
    text = p.read_text()
    if "igodot_touches" in text:
        patched_3d = True
        break

    pattern = re.compile(r'(void\s+Node3DEditorViewport::_sinput\s*\(\s*const\s+Ref<InputEvent>\s*&\s*p_event\s*\)\s*\{)')
    inject = r"""\1
#ifdef IOS_ENABLED
	{
		static HashMap<int, Vector2> igodot_touches;
		Ref<InputEventScreenTouch> st = p_event;
		if (st.is_valid()) {
			if (st->is_pressed()) {
				igodot_touches[st->get_index()] = st->get_position();
			} else {
				igodot_touches.erase(st->get_index());
			}
		}

		Ref<InputEventScreenDrag> sd = p_event;
		if (sd.is_valid()) {
			Vector2 prev_pos = igodot_touches.has(sd->get_index()) ? igodot_touches[sd->get_index()] : sd->get_position();
			igodot_touches[sd->get_index()] = sd->get_position();

			if (igodot_touches.size() == 2) {
				Vector2 other_pos = prev_pos;
				for (const KeyValue<int, Vector2> &E : igodot_touches) {
					if (E.key != sd->get_index()) {
						other_pos = E.value;
						break;
					}
				}

				// 2-finger pan (Shift + Middle-drag)
				Ref<InputEventMouseMotion> mm;
				mm.instantiate();
				mm->set_position(sd->get_position());
				mm->set_relative(sd->get_relative() * 0.5f);
				mm->set_button_mask(MouseButtonMask::MIDDLE);
				mm->set_shift_pressed(true);
				_sinput(mm);

				// 2-finger pinch-to-zoom
				real_t prev_dist = prev_pos.distance_to(other_pos);
				real_t curr_dist = sd->get_position().distance_to(other_pos);
				if (prev_dist > 10.0f && curr_dist > 10.0f) {
					Ref<InputEventMagnifyGesture> mg;
					mg.instantiate();
					mg->set_position((sd->get_position() + other_pos) * 0.5f);
					mg->set_factor(curr_dist / prev_dist);
					_sinput(mg);
				}

				surface->accept_event();
				return;
			} else if (igodot_touches.size() == 1 && _edit.mode == TRANSFORM_NONE) {
				// 1-finger orbit (Middle-drag when not dragging a gizmo)
				Ref<InputEventMouseMotion> mm;
				mm.instantiate();
				mm->set_position(sd->get_position());
				mm->set_relative(sd->get_relative());
				mm->set_button_mask(MouseButtonMask::MIDDLE);
				_sinput(mm);

				surface->accept_event();
				return;
			}
		}
	}
#endif"""

    new_text, count = pattern.subn(inject, text, count=1)
    if count > 0:
        p.write_text(new_text)
        print(f"Patched Xogot-style 3D touch controls in {p}")
        patched_3d = True
        break

if not patched_3d:
    raise RuntimeError("Could not find Node3DEditorViewport::_sinput in node_3d_editor_plugin.cpp")
