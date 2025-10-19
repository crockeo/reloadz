import shutil
import subprocess
from pathlib import Path


def build() -> None:
    proc = subprocess.run(("zig", "build", "lib"))
    if proc.returncode != 0:
        exit()
    src_lib_path = Path.cwd() / "zig-out" / "lib" / "libreloadz.dylib"
    dst_lib_path = Path.cwd() / "reloadz.so"
    shutil.copy(src_lib_path, dst_lib_path)


def make_hot_reloader():
    import reloadz

    return reloadz.HotReloader()


def main() -> None:
    build()
    hot_reloader = make_hot_reloader()
    hot_reloader.parse_file("example.py")


if __name__ == "__main__":
    main()
