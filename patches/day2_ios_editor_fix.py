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

# 2. Patch OS::create_instance in core/os/os.cpp to catch ALL iOS project launches
os_cpp = Path("core/os/os.cpp")
text = os_cpp.read_text()
pattern = re.compile(r'(Error\s+OS::create_instance\s*\([^)]*\)\s*\{)')
inject = r"""\1
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
				std::string flag_file = std::string(home) + "/Documents/.igodot_launch_project";
				FILE *f = fopen(flag_file.c_str(), "w");
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
    patched, count = pattern.subn(inject, text, count=1)
    if count == 0:
        raise RuntimeError("Could not find OS::create_instance in core/os/os.cpp")
    patched = "#include <stdio.h>\n#include <stdlib.h>\n#include <unistd.h>\n#include <string>\n" + patched
    os_cpp.write_text(patched)
    print("Patched OS::create_instance in core/os/os.cpp")

# 3. Patch main/main.cpp: on iOS startup, boot directly into the saved project with --editor
main_cpp = Path("main/main.cpp")
text = main_cpp.read_text()
anchor = "List<String> args;"
inject_main = """List<String> args;
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
    text = "#include <stdio.h>\n#include <stdlib.h>\n#include <string>\n" + text.replace(anchor, inject_main, 1)
    main_cpp.write_text(text)
    print("Patched main/main.cpp to auto-boot selected project on iOS")
