#!/usr/bin/env python3
"""Publish Allo Mokawil release assets, verifying what the server actually stored.

Why this exists: the bash publisher treated "asset exists" as "asset is correct".
It retried into a 422 already_exists, then printed the asset list and called it a
success -- while the release kept serving a *different, stale* binary. A stale
asset with the right name is worse than no asset: the download link looks fine.

Rules enforced here:
  * never trust the upload response code -- re-read the asset list afterwards
  * compare GitHub's own `digest` (sha256:) against the local file's sha256
  * a name collision is resolved by comparing digests, then replacing, not skipping
  * exit non-zero unless every named asset is live AND byte-identical to local

Usage:
  publish_release.py --tag v1.0.5 --file /tmp/apkrel_105/allomokawil-arm64.apk=allomokawil-arm64.apk ...
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com/repos/cheminisifeddine/allomokawil"
UPLOAD = "https://uploads.github.com/repos/cheminisifeddine/allomokawil"


#: Where a token is looked for, in order. Named so the refusal can name every
#: place it actually looked instead of only the first.
TOKEN_PATHS = ("/tmp/ghtok", os.path.expanduser("~/.ghtok"))


def token():
    for path in TOKEN_PATHS:
        if os.path.exists(path):
            t = open(path).read().strip()
            if t:
                return t
    raise SystemExit("no GitHub token found at %s"
                     % ", ".join(TOKEN_PATHS))


#: Read once, on first use. See [_tok] below.
_TOK = None


def _tok():
    """The token, read on first use rather than at import.

    **Why this is not how it was.** `TOK = token()` ran at module scope, which
    made the module un-importable on any machine without a token file: the
    `SystemExit` fired during `import`, before `main()` and before `argparse`.
    Two things that look unrelated were both that one line:

      * `--help` exited 1 printing `no GitHub token found` instead of the usage
        text and exit 0 -- a tool that cannot describe its own arguments.
      * **This file was the one `tool/*.py` in the repo with no test battery**,
        because no test could import it. Every sibling had been fixed already;
        the backlog blamed "founder-gated, never run from the loop" for the gap,
        which is true of *running* it and false of *testing* it.

    Nothing reads the token until an HTTP call is actually about to be made.
    """
    global _TOK
    if _TOK is None:
        _TOK = token()
    return _TOK


def parse_spec(spec, exists=os.path.exists):
    """One `--file` argument, `local_path=asset_name`, as `(path, name)`.

    **String splitting alone cannot answer this, and the first attempt at it
    was wrong.** The obvious rule is "split on the LAST `=`", because a `=` is
    legal inside a path. It is still wrong, and measured: for
    `/tmp/apk=v1/missing.apk` — a path holding one `=` and no asset name —
    `rpartition` yields `('/tmp/apk', 'v1/missing.apk')`, which is **byte for
    byte the same wrong answer** the original `partition("=")` gave. A file
    with an `=` in its directory was already reported as missing under a path
    the caller never typed; changing the split point only moves the error.

    So the separator is decided by **whether the left side exists**, not by
    where the `=` sits:

    1. the whole argument is an existing file -> a plain path, no asset name;
    2. otherwise split on the LAST `=` and use it only when the left side is a
       real file — that is the documented `local_path=asset_name` form;
    3. otherwise there is no valid reading, and the whole argument is returned
       as the path so the caller's "missing local file" names what was typed.

    [exists] is injected so the branch can be driven against a temp directory in
    a test rather than by guessing at paths.
    """
    if exists(spec):
        return spec, ""
    path, sep, name = spec.rpartition("=")
    if sep and exists(path):
        return path, name
    return spec, ""


def upload_url(rid, name):
    """The asset-upload URL for [name], with the name percent-encoded.

    The name went into the query string raw. Ours are `allomokawil-arm64.apk`
    and survive it, but `+` reads back as a space, `&` truncates the query, and
    a name with a space is rejected outright -- which for an Arabic-first app
    whose assets are allowed to carry Arabic names is a silent upload to a
    server-side name nobody asked for.
    """
    return "%s/releases/%s/assets?name=%s" % (UPLOAD, rid,
                                               urllib.parse.quote(name, safe=""))


def req(url, method="GET", data=None, ctype="application/json", raw=None):
    r = urllib.request.Request(url, method=method, data=data or raw)
    r.add_header("Authorization", "token %s" % _tok())
    r.add_header("Accept", "application/vnd.github+json")
    if data is not None or raw is not None:
        r.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(r, timeout=1800) as resp:
            body = resp.read()
            return resp.status, (json.loads(body) if body.strip().startswith(b"{") or body.strip().startswith(b"[") else body)
    except urllib.error.HTTPError as e:
        detail = e.read()
        try:
            return e.code, json.loads(detail)
        except Exception:
            return e.code, detail[:300]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--file", action="append", required=True, help="local_path=asset_name")
    args = ap.parse_args()

    pairs = []
    for spec in args.file:
        path, name = parse_spec(spec)
        if not os.path.exists(path):
            # Names the path exactly as it was typed. Every spelling tried here
            # has ended up blaming a prefix of it, and an operator cannot fix a
            # path they were never shown.
            raise SystemExit("missing local file: %s (from --file %s)"
                             % (path, spec))
        pairs.append((path, name or os.path.basename(path), sha256(path)))

    code, rel = req("%s/releases/tags/%s" % (API, args.tag))
    if code != 200:
        raise SystemExit("release %s not found (http %s): %s" % (args.tag, code, rel))
    rid = rel["id"]
    print("release %s id=%s (%s)" % (args.tag, rid, rel["name"]))
    print("assets now:", ", ".join(a["name"] for a in rel.get("assets", [])) or "(none)")

    for path, name, local in pairs:
        assets = {a["name"]: a for a in req("%s/releases/%s/assets" % (API, rid))[1]}
        cur = assets.get(name)
        if cur:
            server = (cur.get("digest") or "").replace("sha256:", "")
            if server == local:
                print("  %-26s unchanged (digest matches %s)" % (name, local[:12]))
                continue
            print("  %-26s STALE: server=%s local=%s -> replacing" % (name, server[:12] or "?", local[:12]))
            dc, db = req("%s/releases/assets/%s" % (API, cur["id"]), method="DELETE")
            if dc not in (204, 200):
                raise SystemExit("could not delete stale asset %s: %s %s" % (name, dc, db))
        size = os.path.getsize(path)
        print("  %-26s uploading %d bytes ..." % (name, size), flush=True)
        with open(path, "rb") as f:
            payload = f.read()
        ctype = "application/vnd.android.package-archive"
        uc, ub = req(upload_url(rid, name), method="POST", ctype=ctype,
                     raw=payload)
        print("    upload http=%s" % uc)

    print("\nverifying what the server stores:")
    ok = True
    assets = {a["name"]: a for a in req("%s/releases/%s/assets" % (API, rid))[1]}
    for path, name, local in pairs:
        a = assets.get(name)
        if not a:
            print("  %-26s MISSING" % name)
            ok = False
            continue
        server = (a.get("digest") or "").replace("sha256:", "")
        match = server == local
        ok = ok and match and a["state"] == "uploaded"
        print("  %-26s state=%-8s size=%-9d digest=%s %s" % (
            name, a["state"], a["size"], (server[:16] or "?"), "OK" if match else "MISMATCH (local %s)" % local[:16]))
    if not ok:
        raise SystemExit("VERIFICATION FAILED -- do not announce this release")
    print("\nall %d assets live and byte-identical to local builds" % len(pairs))


if __name__ == "__main__":
    main()
