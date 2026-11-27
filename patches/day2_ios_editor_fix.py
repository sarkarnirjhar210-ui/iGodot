from pathlib import Path
import re

# 1. Enable Godot's built-in Tablet/Touchscreen + Single-Window Mode defaults on iOS
for p in Path("editor").rglob("editor_settings.cpp"):
    text = p.read_text()
    patched = text.replace(
        "#ifdef ANDROID_ENABLED",
        "#if defined(ANDROID_ENABLED) || defined(IOS_ENABLED)",
    )
    if patched != text:
        p.write_text(patched)
        print(f"Enabled tablet/touchscreen & single-window defaults in {p}")

# 2. Patch OS_Unix::create_process to handle BOTH Editor launches and Standalone Game launches
os_unix_cpp = Path("drivers/unix/os_unix.cpp")
text = os_unix_cpp.read_text()
pattern = re.compile(r'(Error\s+OS_Unix::create_process\s*\([^)]*\)\s*\{)')
inject_os = r"""\1
#ifdef IOS_ENABLED
	{
		String proj_path;
		String scene_path;
		bool is_editor = false;
		bool take_next = false;
		for (const String &arg : p_arguments) {
			if (take_next) {
				proj_path = arg;
				take_next = false;
				continue;
			}
			if (arg == "--path") {
				take_next = true;
			} else if (arg == "--editor" || arg == "-e") {
				is_editor = true;
			} else if (arg.begins_with("res://") && (arg.ends_with(".tscn") || arg.ends_with(".scn"))) {
				scene_path = arg;
			}
		}
		if (!proj_path.is_empty()) {
			const char *home = getenv("HOME");
			if (home) {
				CharString flag_file = (String(home) + "/Documents/.igodot_launch_project").utf8();
				FILE *f = fopen(flag_file.get_data(), "w");
				if (f) {
					String payload = (is_editor ? "EDITOR\n" : "GAME\n") + proj_path + "\n" + scene_path + "\n";
					CharString cs = payload.utf8();
					fwrite(cs.get_data(), 1, cs.length(), f);
					fclose(f);
				}
			}
			_exit(0);
		}
	}
#endif"""

if ".igodot_launch_project" not in text:
    new_text, count = pattern.subn(inject_os, text, count=1)
    if count == 0:
        raise RuntimeError("Could not find OS_Unix::create_process in drivers/unix/os_unix.cpp")
    os_unix_cpp.write_text(new_text)
    print("Patched OS_Unix::create_process in drivers/unix/os_unix.cpp")

# 3. Patch main/main.cpp: on iOS startup, boot into Editor OR Standalone Game based on launch file
main_cpp = Path("main/main.cpp")
text = main_cpp.read_text()
anchor = "List<String> args;"
inject_main = """List<String> args;
#ifdef IOS_ENABLED
	{
		const char *home = getenv("HOME");
		if (home) {
			CharString flag_path = (String(home) + "/Documents/.igodot_launch_project").utf8();
			FILE *f = fopen(flag_path.get_data(), "r");
			if (f) {
				char mode_buf[64] = { 0 };
				char path_buf[2048] = { 0 };
				char scene_buf[2048] = { 0 };
				String mode_str = fgets(mode_buf, sizeof(mode_buf) - 1, f) ? String::utf8(mode_buf).strip_edges() : "";
				String p_path = fgets(path_buf, sizeof(path_buf) - 1, f) ? String::utf8(path_buf).strip_edges() : "";
				String s_path = fgets(scene_buf, sizeof(scene_buf) - 1, f) ? String::utf8(scene_buf).strip_edges() : "";
				fclose(f);
				remove(flag_path.get_data());

				if (!p_path.is_empty()) {
					args.push_back("--path");
					args.push_back(p_path);
					if (mode_str == "EDITOR") {
						args.push_back("--editor");
					} else if (!s_path.is_empty()) {
						args.push_back(s_path);
					}
				}
			}
		}
	}
#endif"""
if anchor in text and ".igodot_launch_project" not in text:
    text = "#include <stdio.h>\n#include <stdlib.h>\n" + text.replace(anchor, inject_main, 1)
    main_cpp.write_text(text)
    print("Patched main/main.cpp for Editor & Standalone Game launch on iOS")

# 4. Patch SceneTree::quit() so tapping Quit exits cleanly on iOS instead of freezing
st_cpp = Path("scene/main/scene_tree.cpp")
if st_cpp.exists():
    text = st_cpp.read_text()
    if "_exit(p_exit_code)" not in text:
        q_pattern = re.compile(r'(void\s+SceneTree::quit\s*\(\s*int\s+p_exit_code\s*\)\s*\{)')
        q_inject = r"""\1
#ifdef IOS_ENABLED
	_exit(p_exit_code);
#endif"""
        new_text, count = q_pattern.subn(q_inject, text, count=1)
        if count > 0:
            st_cpp.write_text("#ifdef IOS_ENABLED\n#include <unistd.h>\n#endif\n" + new_text)
            print("Patched SceneTree::quit() for clean iOS exit")
