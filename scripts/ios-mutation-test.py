"""Prove the focused core regressions detect broken search, ordering and writes."""

import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cases = [
    (
        "ios/Core/BirthdayListOrder.swift",
        "[.caseInsensitive, .diacriticInsensitive], locale: locale)",
        "[], locale: locale)",
        "BirthdayListTests",
        "case/accent search",
    ),
    (
        "ios/Core/BirthdayListOrder.swift",
        "rule.reversed ? .orderedDescending : .orderedAscending",
        "rule.reversed ? .orderedAscending : .orderedDescending",
        "BirthdayListTests",
        "sort direction",
    ),
    (
        "ios/Core/SomaClient.swift",
        '_ = try await contract.validate(request(path: "v1/session", maximumBytes: 65_536))',
        "// Deliberately removed for mutation verification.",
        "OptInTests",
        "live session authorization",
    ),
]

for relative, old, new, tests, name in cases:
    path = root / relative
    original = path.read_text()
    if original.count(old) != 1:
        raise SystemExit(f"Mutation target changed: {name}")
    try:
        path.write_text(original.replace(old, new))
        result = subprocess.run(
            ["swift", "test", "--scratch-path", sys.argv[1], "--filter", tests],
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
            check=False,
        )
        if result.returncode == 0 or "XCTAssert" not in result.stdout:
            print(result.stdout[-6000:])
            raise SystemExit(f"Mutation did not fail a behavioral assertion: {name}")
        print(f"Detected: {name}")
    finally:
        path.write_text(original)
