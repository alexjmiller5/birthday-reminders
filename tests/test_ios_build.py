"""Exercise artifact export without a signing identity or physical device."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


@pytest.mark.skipif(shutil.which("just") is None, reason="requires just")
def test_release_installs_the_ipa_from_the_unique_export_directory(tmp_path):
    root = Path(__file__).resolve().parents[1]
    shutil.copy(root / "ios" / "justfile", tmp_path / "justfile")
    binaries = tmp_path / "bin"
    binaries.mkdir()
    programs = {
        "xcodegen": "pass",
        "security": "print('Apple Distribution')",
        "plutil": "print('com.example.BirthdayReminders')",
        "xcodebuild": """
import sys
from pathlib import Path
args = sys.argv[1:]
if '-exportPath' in args:
    export = Path(args[args.index('-exportPath') + 1])
    export.mkdir(parents=True, exist_ok=True)
    (export / 'BirthdayReminders.ipa').write_bytes(b'signed-test-artifact')
""",
        "xcrun": """
import sys
from pathlib import Path
assert sys.argv[1:5] == ['devicectl', 'device', 'install', 'app']
assert Path(sys.argv[-1]).read_bytes() == b'signed-test-artifact'
Path('installed').write_text('yes')
""",
    }
    for name, program in programs.items():
        path = binaries / name
        path.write_text(f"#!{sys.executable}\n{program}\n")
        path.chmod(0o755)
    derived = tmp_path / "derived data"
    derived.mkdir()
    env = {
        **os.environ,
        "PATH": f"{binaries}{os.pathsep}{os.environ['PATH']}",
        "IOS_DERIVED_DATA": str(derived),
        "IOS_DEVICE_ID": "test-device",
        "IOS_DEVELOPMENT_TEAM": "test-team",
        "IOS_PROFILE": "test-profile",
        "IOS_INSTALL_HOST": "",
    }
    result = subprocess.run(
        ["just", "deploy"], cwd=tmp_path, env=env, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / "installed").read_text() == "yes"
    assert (tmp_path / "build" / "BirthdayReminders.ipa").read_bytes() == b"signed-test-artifact"
