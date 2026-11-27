from pathlib import Path

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

# 2. Patch Project Manager: on iOS, save selected project path & quit cleanly instead of fork()
for p in Path("editor").rglob("project_manager.cpp"):
    text = p.read_text()
    target = "Error err = OS::get_singleton()->create_instance(args);"
    replacement = """#ifdef IOS_ENABLED
	{
		String proj_path;
		bool take_next = false;
		for (const String &arg : args) {
			if (take_next) {
				proj_path = arg;
				break;
			}
			if (arg == "--path") {
				take_next = true;
			}
		}
		if (!proj_path.is_empty()) {
			const char *home = getenv("HOME");
			if (home) {
				String flag_file = String(home) + "/Documents/.igodot_launch_project";
				Ref<FileAccess> f = FileAccess::open(flag_file, FileAccess::WRITE);
				if (f.is_valid()) {
					f->store_string(proj_path);
					f->close();
				}
			}
			get_tree()->quit();
			return;
		}
	}
#endif
	Error err = OS::get_singleton()->create_instance(args);"""
    if target in text and ".igodot_launch_project" not in text:
        text = "#include <stdlib.h>\n" + text.replace(target, replacement, 1)
        p.write_text(text)
        print(f"Patched iOS project launcher in {p}")

# 3. Patch main/main.cpp: on iOS startup, boot directly into the saved project with --editor
main_cpp = Path("main/main.cpp")
text = main_cpp.read_text()
anchor = "List<String> args;"
inject = """List<String> args;
#ifdef IOS_ENABLED
	{
		const char *home = getenv("HOME");
		if (home) {
			std::string flag_path = std::string(home) + "/Documents/.igodot_launch_project";
			FILE *f = fopen(flag_path.c_str(), "r");
			if (f) {
				char buf[2048] = { 0 };
				if (fgets(buf, sizeof(buf) - 1, f)) {
					String p_path = String::utf8(buf).strip_edges();
					if (!p_path.is_empty()) {
						args.push_back("--path");
						args.push_back(p_path);
						args.push_back("--editor");
					}
				}
				fclose(f);
				remove(flag_path.c_str());
			}
		}
	}
#endif"""
if anchor in text and ".igodot_launch_project" not in text:
    text = "#include <stdio.h>\n#include <stdlib.h>\n#include <string>\n" + text.replace(anchor, inject, 1)
    main_cpp.write_text(text)
    print("Patched main/main.cpp to auto-boot selected project on iOS")
