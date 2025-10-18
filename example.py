import shutil
import subprocess
from pathlib import Path

proc = subprocess.run(("zig", "build", "lib"))
if proc.returncode != 0:
    exit()
src_lib_path = Path.cwd() / "zig-out" / "lib" / "libexample_python_library.dylib"
dst_lib_path = Path.cwd() / "spam.so"
shutil.copy(src_lib_path, dst_lib_path)
import spam

print(spam.example(1))
