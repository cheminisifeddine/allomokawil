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
import urllib.request

API = "https://api.github.com/repos/cheminisifeddine/allomokawil"
UPLOAD = "https://uploads.github.com/repos/cheminisifeddine/allomokawil"


def token():
    for path in ("/tmp/ghtok", os.path.expanduser("~/.ghtok")):
        if os.path.exists(path):
            t = open(path).read().strip()
            if t:
                return t
    raise SystemExit("no GitHub token found at /tmp/ghtok")


TOK = token()


def req(url, method="GET", data=None, ctype="application/json", raw=None):
    r = urllib.request.Request(url, method=method, data=data or raw)
    r.add_header("Authorization", "token %s" % TOK)
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
        path, _, name = spec.partition("=")
        if not os.path.exists(path):
            raise SystemExit("missing local file: %s" % path)
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
        uc, ub = req("%s/releases/%s/assets?name=%s" % (UPLOAD, rid, name),
                     method="POST", ctype=ctype, raw=payload)
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
