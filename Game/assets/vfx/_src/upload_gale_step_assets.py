"""Spin for Abilities - Gale Step, stage 4: upload textures, meshes and the animation with Open Cloud.

    python upload_gale_step_assets.py            (system Python, standard library only)
Key: ROBLOX_OPEN_CLOUD_KEY in Game/.env (git-ignored). The creator is the key's owner (read from
the key itself), which must be the game's owner so the animation is allowed to play.

    textures (PNG)        -> assetType Image  (the image id itself; a Decal upload returns a decal id)
    meshes (FBX)          -> assetType Model  (a Model holding one MeshPart; Studio reads its MeshId)
    gale_step_dash.rbxmx  -> assetType Animation

Results go to Game/assets/vfx/gale_step_assets.json, keyed by file with its SHA-256: a file that is
already uploaded with the same content is skipped, so rerunning never makes duplicates.
"""
import hashlib, json, os, sys, time, uuid, urllib.request, urllib.error

GAME = r"C:\Roblox\Spin for ability\Game"
ENV = os.path.join(GAME, ".env")
RESULTS = os.path.join(GAME, "assets", "vfx", "gale_step_assets.json")
API = "https://apis.roblox.com"
TEX = os.path.join(GAME, "assets", "vfx", "textures")
FILES = [  # (key, path, assetType, content type, display name)
    *[(n, os.path.join(TEX, n + ".png"), "Image", "image/png", f"GaleStep {n}") for n in
      ("wind_gradient", "wind_streaks", "sparkle", "soft_glow", "wind_wisp", "wind_swirl_flipbook")],
    *[(n, os.path.join(GAME, "assets", n + ".fbx"), "Model", "model/fbx", f"GaleStep {n}") for n in
      ("wind_crescent_a", "wind_crescent_b", "wind_ring", "wind_spiral")],
    ("gale_step_dash", os.path.join(GAME, "assets", "gale_step_dash.rbxmx"), "Animation", "model/x-rbxm",
     "GaleStep Dash"),
]


def api_key():
    with open(ENV) as fh:
        for line in fh:
            if line.startswith("ROBLOX_OPEN_CLOUD_KEY="):
                return line.split("=", 1)[1].strip().strip("<>").strip()
    sys.exit("ROBLOX_OPEN_CLOUD_KEY missing from Game/.env")


def request(method, url, key=None, body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method, headers=dict(headers or {}))
    if key:
        req.add_header("x-api-key", key)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", "replace")[:800]}


def creator_id(key):
    status, data = request("POST", f"{API}/api-keys/v1/introspect", body=json.dumps({"apiKey": key}).encode(),
                           headers={"Content-Type": "application/json"})
    if status != 200:
        sys.exit(f"key check failed: {status} {data}")
    return data["authorizedUserId"]


def upload(key, creator, path, asset_type, content_type, name):
    boundary = uuid.uuid4().hex
    meta = {"assetType": asset_type, "displayName": name[:50],
            "description": "Spin for Abilities - Gale Step VFX (made in Blender)",
            "creationContext": {"creator": {"userId": str(creator)}}}
    with open(path, "rb") as fh:
        data = fh.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
            f"Content-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; "
            f"filename=\"{os.path.basename(path)}\"\r\nContent-Type: {content_type}\r\n\r\n").encode() + data + \
           f"\r\n--{boundary}--\r\n".encode()
    status, op = request("POST", f"{API}/assets/v1/assets", key, body,
                         {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    if status != 200:
        return None, f"upload HTTP {status}: {op}"
    for _ in range(60):
        if op.get("done"):
            resp = op.get("response") or {}
            if "assetId" in resp:
                return resp["assetId"], None
            return None, f"operation finished without an asset: {op}"
        time.sleep(2)
        status, op = request("GET", f"{API}/assets/v1/{op['path']}", key)
        if status != 200:
            return None, f"poll HTTP {status}: {op}"
    return None, "timed out waiting for the upload to finish"


def main():
    key = api_key()
    creator = creator_id(key)
    results = json.load(open(RESULTS)) if os.path.exists(RESULTS) else {}
    failed = 0
    for name, path, asset_type, content_type, display in FILES:
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        prev = results.get(name)
        if prev and prev.get("sha256") == digest and prev.get("assetId") and prev.get("assetType") == asset_type:
            print(f"{name:20s} unchanged, keeping {prev['assetId']}")
            continue
        asset_id, err = upload(key, creator, path, asset_type, content_type, display)
        if err:
            failed += 1
            print(f"{name:20s} FAILED: {err}")
            continue
        results[name] = {"assetId": str(asset_id), "assetType": asset_type, "sha256": digest,
                         "file": os.path.relpath(path, GAME).replace("\\", "/"), "creatorUserId": creator}
        print(f"{name:20s} {asset_type:9s} -> {asset_id}")
        with open(RESULTS, "w") as fh:
            json.dump(results, fh, indent=1)
    print(f"done, {failed} failed; ids in {RESULTS}")


main()
