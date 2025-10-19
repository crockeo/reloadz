import shutil
import subprocess
from pathlib import Path

proc = subprocess.run(("zig", "build", "lib"))
if proc.returncode != 0:
    exit()
src_lib_path = Path.cwd() / "zig-out" / "lib" / "libreloadz.dylib"
dst_lib_path = Path.cwd() / "reloadz.so"
shutil.copy(src_lib_path, dst_lib_path)
import reloadz

hot_reloader = reloadz.HotReloader()
print(hot_reloader)
# print(hot_reloader)

# print(reloadz.example(1))
