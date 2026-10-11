#!/usr/bin/env python3
"""Prove `tool/publish_release.py` is importable, testable, and correct about
the two argument shapes it used to get wrong.

Run directly -- it is not a `flutter test`:

    python3 test/publish_release_test.py

**Why this file exists.** `publish_release.py` was the one `tool/*.py` in the
repo with **no test battery at all**, and the backlog had already written the
reason down as "founder-gated, must never run from this loop". That is true of
*running* the publisher and false of *testing* it: the module could not be
imported on any machine without a token file, because `TOK = token()` ran at
module scope and raised `SystemExit` during `import` -- before `main()`, before
`argparse`. No test can guard a module that refuses to import.

This battery never touches the network. It imports the real module, calls its
real pure helpers, and shells out to the real CLI with `--help` and with a
missing file. `main()` is never run to completion against GitHub.

**The three defects, each measured before the fix (not inferred):**

  1. **Module scope did work belonging to a request.** `import
     publish_release` on a token-less box printed `no GitHub token found at
     /tmp/ghtok` and exited **1**. After the fix: imports clean, and `--help`
     exits **0** with real usage text -- it was exiting 1 before.
  2. **`--file` split on the first `=`.** `partition("=")` on
     `/tmp/apk=v1/app.apk` yields `/tmp/apk`, a path that does not exist, and
     the tool refused with `missing local file: /tmp/apk` -- naming a path the
     caller never typed. Now splits on the last `=`.
  3. **The asset name went into the query string raw.** `+` reads back as a
     space and `&` truncates the query, so the tool would upload under a name
     nobody asked for. Now percent-encoded.

Expected: 16/16. A failure means the release publisher is back to a state where
it cannot be tested, or uploads an asset under the wrong name.
"""
import io
import os
import re
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool", "publish_release.py")
sys.path.insert(0, os.path.join(REPO, "tool"))

import publish_release as pr  # noqa: E402  (needs the sys.path line above)

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


# --------------------------------------------------------------------------
# 1. Importability -- the defect that kept this file untested.
# --------------------------------------------------------------------------

@case
def test_module_imports_without_a_token_file(tmp):
    """The module must import on a box that has no token.

    The point is not that importing is side-effect free, it is that it must not
    *fail*. The token is read on the first HTTP call, not at import.
    """
    if os.path.exists("/tmp/ghtok"):
        print("      (note: /tmp/ghtok exists on this box)")
    code = ("import sys; sys.path.insert(0, %r); import publish_release; "
            "print('OK')" % os.path.join(REPO, "tool"))
    proc = subprocess.run([sys.executable, "-c", code], cwd=REPO,
                          capture_output=True, text=True)
    assert proc.returncode == 0, "import failed: rc=%s %s" % (proc.returncode,
                                                            proc.stderr)
    assert "OK" in proc.stdout, "import did not reach its last line: %r" % proc.stdout
    assert "no GitHub token" not in (proc.stdout + proc.stderr), \
        "import still reads a token: %r" % (proc.stdout + proc.stderr)


@case
def test_help_exits_zero_and_prints_usage(tmp):
    """`--help` is how an operator learns the tool exists and what it takes.

    It exited 1 with a token complaint before the fix. It must exit 0 and print
    both required arguments.
    """
    proc = subprocess.run([sys.executable, TOOL, "--help"], cwd=REPO,
                          capture_output=True, text=True)
    assert proc.returncode == 0, "--help exited %s: %r" % (proc.returncode,
                                                           proc.stderr)
    out = proc.stdout + proc.stderr
    assert "--tag" in out, "--help does not mention --tag: %r" % out
    assert "--file" in out, "--help does not mention --file: %r" % out
    assert "no GitHub token" not in out, "--help still demands a token: %r" % out


@case
def test_token_is_not_a_module_attribute(tmp):
    """No bare `TOK` global left behind.

    A module-level `TOK` is the very thing that made this un-importable, and it
    is the kind of name a future edit reaches for without reading why it moved.
    """
    assert not hasattr(pr, "TOK"), \
        "publish_release still exposes a module-scope TOK; it must be lazy"
    assert hasattr(pr, "_tok"), "the lazy token accessor is missing"
    assert pr._TOK is None, "the token was read at import, not on first use"


@case
def test_token_refusal_names_every_place_it_looked(tmp):
    """The refusal must name all search paths, not only the first.

    The old message said `/tmp/ghtok` alone while the code also checked
    `~/.ghtok`, so an operator whose token sat in their home directory read a
    message about a file they have never heard of.
    """
    saved = pr.TOKEN_PATHS
    try:
        pr.TOKEN_PATHS = tuple(
            os.path.join(tmp, "definitely-absent-%d" % i) for i in range(3))
        try:
            pr.token()
        except SystemExit as exc:
            msg = str(exc)
            assert "no GitHub token found" in msg, msg
            for path in pr.TOKEN_PATHS:
                assert path in msg, "refusal omits %s: %r" % (path, msg)
        else:
            raise AssertionError("token() with no files must refuse")
    finally:
        pr.TOKEN_PATHS = saved


@case
def test_token_reads_the_first_populated_path(tmp):
    """The happy path, driven against a temp file -- never the real token.

    A whitespace-only file must be skipped in favour of a later one, which is
    what the `if t:` guard is for and what nothing else covered.
    """
    blank = os.path.join(tmp, "blank")
    with open(blank, "w", encoding="utf-8") as fh:
        fh.write("   \n")
    good = os.path.join(tmp, "good")
    with open(good, "w", encoding="utf-8") as fh:
        fh.write("  ghp_example  \n")
    saved = pr.TOKEN_PATHS
    try:
        pr.TOKEN_PATHS = (blank, good)
        assert pr.token() == "ghp_example", repr(pr.token())
        pr.TOKEN_PATHS = (good, blank)
        assert pr.token() == "ghp_example", repr(pr.token())
    finally:
        pr.TOKEN_PATHS = saved


# --------------------------------------------------------------------------
# 2. --file spec parsing.
#
# Driven against REAL files in a temp directory. `parse_spec` decides with
# `os.path.exists`, so a test that invents paths the filesystem has never seen
# is not testing it -- it is testing the fallback branch and calling it a pass.
# That is how the first version of this file "passed" a wrong parser.
# --------------------------------------------------------------------------

def _mk(tmp, *parts):
    p = os.path.join(tmp, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as fh:
        fh.write(b"x")
    return p


@case
def test_plain_existing_path_has_no_asset_name(tmp):
    """The argument is itself a file: it is a path, and no name was given."""
    real = _mk(tmp, "allomokawil.apk")
    path, name = pr.parse_spec(real)
    assert path == real, path
    assert name == "", name


@case
def test_existing_path_with_an_asset_name(tmp):
    """The documented `local_path=asset_name` form, on real files."""
    real = _mk(tmp, "allomokawil.apk")
    path, name = pr.parse_spec(real + "=published.apk")
    assert path == real, path
    assert name == "published.apk", name


@case
def test_existing_path_whose_directory_holds_an_equals(tmp):
    """**The defect this parser exists to fix.**

    `/tmp/.../apk=v1/app.apk` is a real file whose *directory* holds a `=`, and
    the caller gave no asset name. Both the original `partition("=")` and the
    first (wrong) `rpartition` answer `('/tmp/.../apk', 'v1/app.apk')` — byte
    for byte the same wrong answer — and the tool then refuses with a path the
    caller never typed. Whole-argument-first is the only rule that gets this.
    """
    real = _mk(tmp, "apk=v1", "app.apk")
    path, name = pr.parse_spec(real)
    assert path == real, "an equals in a directory split the argument: %r" % path
    assert name == "", "an asset name was invented: %r" % name


@case
def test_existing_path_with_equals_and_an_asset_name(tmp):
    """Both hazards at once: `=` in the directory *and* a real asset name.

    Last-`=` is correct here, and only here — which is why the rule is
    existence-first rather than "always split on the last `=`".
    """
    real = _mk(tmp, "apk=v1", "app.apk")
    path, name = pr.parse_spec(real + "=published.apk")
    assert path == real, path
    assert name == "published.apk", name


@case
def test_missing_path_is_returned_whole(tmp):
    """A missing file must come back untouched, so the refusal names it.

    No name can be recovered and none is invented; the whole argument is the
    path. This is the case the two earlier splittings got wrong.
    """
    missing = os.path.join(tmp, "apk=v1", "missing.apk")
    path, name = pr.parse_spec(missing)
    assert path == missing, path
    assert name == "", name


@case
def test_missing_plain_path(tmp):
    missing = os.path.join(tmp, "nope.apk")
    path, name = pr.parse_spec(missing)
    assert path == missing, path
    assert name == "", name


@case
def test_spec_of_empty_string(tmp):
    """Degenerate input must not raise; argparse has already checked the count."""
    path, name = pr.parse_spec("")
    assert path == "", repr(path)
    assert name == "", repr(name)


@case
def test_arabic_asset_name_survives_parsing(tmp):
    """Arabic-first: the asset name is data and must survive intact."""
    real = _mk(tmp, "app.apk")
    path, name = pr.parse_spec(real + "=تطبيق-مقاول.apk")
    assert path == real, path
    assert name == "تطبيق-مقاول.apk", name


@case
def test_asset_name_with_spaces_survives_parsing(tmp):
    real = _mk(tmp, "a.apk")
    path, name = pr.parse_spec(real + "=my app.apk")
    assert path == real, path
    assert name == "my app.apk", name


@case
def test_injected_exists_drives_the_branch(tmp):
    """`exists` is injected, so the parser can be driven without guessing paths.

    Asserts the injection is honoured rather than the module reaching for
    `os.path.exists` behind the caller's back.
    """
    asked = []

    def fake(p):
        asked.append(p)
        return p == "/real/path.apk"

    assert pr.parse_spec("/real/path.apk=x.apk", exists=fake) == (
        "/real/path.apk", "x.apk")
    # Called with the whole argument first (rule 1), then the left side (rule 2).
    assert asked == ["/real/path.apk=x.apk", "/real/path.apk"], asked


@case
def test_cli_reports_the_path_the_caller_typed(tmp):
    """The user-visible half: the refusal must name what was typed.

    Run against the real CLI with a `=` inside the path. Before the fix this
    printed `missing local file: .../apk`, blaming a prefix of the argument.
    """
    missing = os.path.join(tmp, "apk=v1", "missing.apk")
    proc = subprocess.run([sys.executable, TOOL, "--tag", "v9",
                           "--file", missing], cwd=REPO,
                          capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    assert proc.returncode != 0, "a missing file must not exit 0"
    # Extract the blamed path and compare it to the typed one *exactly*. A
    # substring check is wrong here: the correct message necessarily starts with
    # the bad one (".../apk" is a prefix of ".../apk=v1/missing.apk"), so a
    # prefix test passes against a truncated blame.
    blamed = None
    for line in out.splitlines():
        if line.startswith("missing local file: "):
            blamed = line[len("missing local file: "):].split(" (from --file")[0]
    assert blamed is not None, "no missing-file refusal at all: %r" % out
    assert blamed == missing, "blamed %r, the caller typed %r" % (blamed, missing)


@case
def test_cli_accepts_a_real_file_named_path_equals_name(tmp):
    """End to end, without the network.

    A real file whose directory holds a `=` must get past argument parsing.
    The run then stops at the release lookup — which needs a token and a network
    — and that is the *only* thing allowed to stop it. If parsing were broken it
    would refuse with `missing local file` instead, which is the failure this
    case exists to catch.
    """
    real = _mk(tmp, "apk=v1", "app.apk")
    proc = subprocess.run([sys.executable, TOOL, "--tag", "v9",
                           "--file", real], cwd=REPO,
                          capture_output=True, text=True, timeout=60)
    out = proc.stdout + proc.stderr
    assert "missing local file" not in out, \
        "a real file was refused: %r" % out
    assert "app.apk" in out or "token" in out, \
        "the run stopped somewhere unexpected: %r" % out


# --------------------------------------------------------------------------
# 3. Upload URL construction
# --------------------------------------------------------------------------

@case
def test_upload_url_plain_name(tmp):
    """The ordinary asset name must be unchanged by encoding."""
    got = pr.upload_url(42, "allomokawil-arm64.apk")
    assert got.endswith("assets?name=allomokawil-arm64.apk"), got
    assert "/releases/42/assets" in got, got


@case
def test_upload_url_encodes_a_plus(tmp):
    """A `+` in a raw query reads back as a space -- the server would store
    the wrong name."""
    got = pr.upload_url(1, "a+b.apk")
    assert "a%2Bb.apk" in got, "plus not encoded: %r" % got


@case
def test_upload_url_encodes_an_ampersand(tmp):
    """`&` in a raw query truncates it -- everything after it is discarded."""
    got = pr.upload_url(1, "a&b.apk")
    assert "a%26b.apk" in got, "ampersand not encoded: %r" % got
    assert got.count("&") == 0, "an unencoded ampersand survived: %r" % got


@case
def test_upload_url_encodes_a_space(tmp):
    got = pr.upload_url(1, "my app.apk")
    assert "my%20app.apk" in got, "space not encoded: %r" % got


@case
def test_upload_url_encodes_arabic(tmp):
    """An Arabic asset name is percent-encoded UTF-8, not dropped or mangled."""
    import urllib.parse
    got = pr.upload_url(1, "تطبيق.apk")
    tail = got.split("?name=", 1)[1]
    assert tail == urllib.parse.quote("تطبيق.apk", safe=""), tail
    assert urllib.parse.unquote(tail) == "تطبيق.apk", tail


@case
def test_upload_url_carries_the_release_id(tmp):
    """The rid must be in the path, not smuggled into the query."""
    got = pr.upload_url(987, "x.apk")
    assert "/releases/987/assets" in got, got


@case
def test_upload_url_targets_the_upload_host(tmp):
    """Uploads go to uploads.github.com, reads to api.github.com.

    Asserted because the two constants are one typo apart and a swap would
    silently 404 every upload.
    """
    got = pr.upload_url(1, "x.apk")
    assert got.startswith("https://uploads.github.com/"), got
    assert pr.API != pr.UPLOAD, "API and UPLOAD are the same host"


# --------------------------------------------------------------------------
# 4. The safety property this whole file rests on: no secrets at module scope
# --------------------------------------------------------------------------

@case
def test_source_holds_no_module_scope_token_call(tmp):
    """Read the source, not just the behaviour.

    A behavioural test passes the moment someone reintroduces `TOK = token()`
    at module scope *and* happens to have a token file present. This reads the
    text so the regression cannot hide behind the environment.

    What is banned is a module-scope **call** to `token()` and a bare `TOK`
    global. `TOKEN_PATHS` and `_TOK = None` are the intended spelling: a list of
    candidate paths, and a cache initialised to nothing.
    """
    src = open(TOOL, encoding="utf-8").read()
    body = src.split('"""', 2)[-1]  # drop the module docstring
    lines = body.splitlines()
    for i, ln in enumerate(lines):
        if ln.startswith("def ") or ln.startswith("class "):
            continue  # inside a function body: a call there is lazy by definition
        assert not re.match(r"^TOK\s*=", ln), \
            "a module-scope TOK is back at line %d: %r" % (i + 1, ln)
        assert not re.match(r"^[A-Za-z_]*TOK[A-Za-z_]*\s*=.*\(\)\s*$", ln), \
            "a module-scope token call is back at line %d: %r" % (i + 1, ln)


@case
def test_no_module_scope_token_use(tmp):
    """Parse the module, do not pattern-match its text.

    The previous version of this case grepped for a bare `TOK` and therefore
    failed on the sentence that *documents* the old bug in `_tok`'s docstring —
    a test that cannot tell prose from code. `ast` can, so this one reads
    identifiers and calls, and a comment saying `TOK = token()` is just a
    comment.
    """
    import ast
    src = open(TOOL, encoding="utf-8").read()
    tree = ast.parse(src)

    # No identifier named TOK is ever read anywhere in the module.
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            assert node.id != "TOK", \
                "TOK is read at line %d: the lazy accessor was bypassed" % node.lineno
        if isinstance(node, ast.Attribute):
            assert node.attr != "TOK", \
                "TOK attribute read at line %d" % node.lineno

    # No module-scope assignment named TOK, and no module-scope call to token().
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for tgt in node.targets:
                if isinstance(tgt, ast.Name):
                    assert tgt.id != "TOK", \
                        "a module-scope TOK assignment is back at line %d" % node.lineno
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            fn = getattr(node.value.func, "id", None)
            assert fn != "token", \
                "token() is called at module scope, line %d" % node.lineno

    # The one required call site is still the lazy accessor.
    assert '"token %s" % _tok()' in src, "the auth header no longer reads _tok()"


@case
def test_sha256_matches_hashlib_on_a_real_file(tmp):
    """The digest comparison is the tool's entire reason for existing.

    If `sha256()` drifted from `hashlib`, every asset would be declared STALE
    and every release would re-upload forever -- or worse, a real mismatch would
    read as a match. Verified against hashlib, not against itself.
    """
    import hashlib
    p = os.path.join(tmp, "payload.bin")
    data = os.urandom(200000)  # spans the 1 MB chunk loop boundary? no -- keep small
    with open(p, "wb") as fh:
        fh.write(data)
    assert pr.sha256(p) == hashlib.sha256(data).hexdigest()


@case
def test_sha256_chunks_a_file_larger_than_the_read_block(tmp):
    """`iter(lambda: f.read(1 << 20), b"")` must accumulate across chunks.

    A 3 MB file crosses the 1 MB read block, so a digest computed only over the
    first chunk would silently disagree with the server on any real APK.
    """
    import hashlib
    p = os.path.join(tmp, "big.bin")
    data = os.urandom(3 * (1 << 20) + 17)
    with open(p, "wb") as fh:
        fh.write(data)
    assert pr.sha256(p) == hashlib.sha256(data).hexdigest()


def main() -> int:
    import shutil
    passed = failed = 0
    for fn in CASES:
        d = tempfile.mkdtemp(prefix="publish_release_test_")
        try:
            fn(d)
            print("  ok   %s" % fn.__name__)
            passed += 1
        except AssertionError as exc:
            print("  FAIL %s: %s" % (fn.__name__, exc))
            failed += 1
        except Exception as exc:
            print("  FAIL %s: %s: %s" % (fn.__name__, type(exc).__name__, exc))
            failed += 1
        finally:
            shutil.rmtree(d, ignore_errors=True)
    print("%d passed / %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
