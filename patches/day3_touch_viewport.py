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

# 2. Add 1-finger orbit + 2-finger pinch-to-zoom (joysticks handle pan/movement)
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

				// 2-finger pinch-to-zoom
				real_t prev_dist = prev_pos.distance_to(other_pos);
				real_t curr_dist = sd->get_position().distance_to(other_pos);
				if (prev_dist > 10.0f && curr_dist > 10.0f && Math::abs(curr_dist - prev_dist) > 1.0f) {
					Ref<InputEventMagnifyGesture> mg;
					mg.instantiate();
					mg->set_position((sd->get_position() + other_pos) * 0.5f);
					mg->set_factor(curr_dist / prev_dist);
					_sinput(mg);
				}

				surface->accept_event();
				return;
			} else if (igodot_touches.size() == 1 && _edit.mode == TRANSFORM_NONE && _edit.gizmo.is_null()) {
				// 1-finger orbit (only when not dragging a transform or CSG resize gizmo)
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
        print(f"Patched 3D touch controls in {p}")
        patched_3d = True
        break

if not patched_3d:
    raise RuntimeError("Could not find Node3DEditorViewport::_sinput in node_3d_editor_plugin.cpp")

# 3. Add native iOS Long-Press (500ms) -> Right-Click context menu in core/input/input.cpp
input_cpp = Path("core/input/input.cpp")
if input_cpp.exists():
    text = input_cpp.read_text()
    if "igodot_lp" not in text:
        includes = list(re.finditer(r'^#include\s+[^\n]+\n', text, re.MULTILINE))
        if not includes:
            raise RuntimeError("Could not find #include in core/input/input.cpp")
        insert_pos = includes[-1].end()
        lp_state = """
#ifdef IOS_ENABLED
namespace {
struct IGodotLongPressState {
	bool active = false;
	bool fired = false;
	uint64_t start_msec = 0;
	Vector2 start_pos;
};
static IGodotLongPressState igodot_lp;
} // namespace
#endif
"""
        text = text[:insert_pos] + lp_state + text[insert_pos:]

        # Track touch press/release/drag in Input::_parse_input_event_impl (takes standard Ref<InputEvent>)
        parse_pat = re.compile(r'(void\s+Input::_parse_input_event_impl\s*\([^)]*\)\s*\{)', re.DOTALL)
        parse_inj = r"""\1
#ifdef IOS_ENABLED
	{
		Ref<InputEventScreenTouch> lp_st = p_event;
		if (lp_st.is_valid()) {
			if (lp_st->is_pressed()) {
				if (lp_st->get_index() == 0) {
					igodot_lp.active = true;
					igodot_lp.fired = false;
					igodot_lp.start_msec = OS::get_singleton()->get_ticks_msec();
					igodot_lp.start_pos = lp_st->get_position();
				} else {
					igodot_lp.active = false;
				}
			} else if (lp_st->get_index() == 0) {
				igodot_lp.active = false;
			}
		}
		Ref<InputEventScreenDrag> lp_sd = p_event;
		if (lp_sd.is_valid() && lp_sd->get_index() == 0 && igodot_lp.active) {
			if (lp_sd->get_position().distance_to(igodot_lp.start_pos) > 18.0f) {
				igodot_lp.active = false;
			}
		}
	}
#endif"""
        text, c1 = parse_pat.subn(parse_inj, text, count=1)

        # Fire right-click in Input::flush_buffered_events
        flush_pat = re.compile(r'(void\s+Input::flush_buffered_events\s*\(\s*\)\s*\{)')
        flush_inj = r"""\1
#ifdef IOS_ENABLED
	if (igodot_lp.active && !igodot_lp.fired && (OS::get_singleton()->get_ticks_msec() - igodot_lp.start_msec) >= 500) {
		igodot_lp.fired = true;
		igodot_lp.active = false;

		Ref<InputEventMouseButton> mb_cancel;
		mb_cancel.instantiate();
		mb_cancel->set_button_index(MouseButton::LEFT);
		mb_cancel->set_pressed(false);
		mb_cancel->set_position(igodot_lp.start_pos);
		mb_cancel->set_global_position(igodot_lp.start_pos);
		parse_input_event(Ref<InputEvent>(mb_cancel));

		Ref<InputEventMouseButton> mb_down;
		mb_down.instantiate();
		mb_down->set_button_index(MouseButton::RIGHT);
		mb_down->set_button_mask(MouseButtonMask::RIGHT);
		mb_down->set_pressed(true);
		mb_down->set_position(igodot_lp.start_pos);
		mb_down->set_global_position(igodot_lp.start_pos);
		parse_input_event(Ref<InputEvent>(mb_down));

		Ref<InputEventMouseButton> mb_up;
		mb_up.instantiate();
		mb_up->set_button_index(MouseButton::RIGHT);
		mb_up->set_pressed(false);
		mb_up->set_position(igodot_lp.start_pos);
		mb_up->set_global_position(igodot_lp.start_pos);
		parse_input_event(Ref<InputEvent>(mb_up));
	}
#endif"""
        text, c2 = flush_pat.subn(flush_inj, text, count=1)

        if c1 == 0 or c2 == 0:
            raise RuntimeError(f"Failed to patch long-press in core/input/input.cpp (c1={c1}, c2={c2})")
        input_cpp.write_text(text)
        print("Patched iOS 500ms long-press right-click in core/input/input.cpp")
