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

# 2. Patch OS_Unix::create_process in drivers/unix/os_unix.cpp to catch ALL iOS project launches
os_unix_cpp = Path("drivers/unix/os_unix.cpp")
text = os_unix_cpp.read_text()
pattern = re.compile(r'(Error\s+OS_Unix::create_process\s*\([^)]*\)\s*\{)')
inject_os = r"""\1
#ifdef IOS_ENABLED
	{
		String proj_path;
		bool take_next = false;
		for (const String &arg : p_arguments) {
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
				CharString flag_file = (String(home) + "/Documents/.igodot_launch_project").utf8();
				FILE *f = fopen(flag_file.get_data(), "w");
				if (f) {
					CharString cs = proj_path.utf8();
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

# 3. Patch main/main.cpp: on iOS startup, boot directly into the saved project with --editor
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
				remove(flag_path.get_data());
			}
		}
	}
#endif"""
if anchor in text and ".igodot_launch_project" not in text:
    text = "#include <stdio.h>\n#include <stdlib.h>\n" + text.replace(anchor, inject_main, 1)
    main_cpp.write_text(text)
    print("Patched main/main.cpp to auto-boot selected project on iOS")
