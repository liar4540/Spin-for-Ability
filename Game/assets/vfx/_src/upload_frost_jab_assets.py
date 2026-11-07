"""Spin for Abilities - Frost Jab: upload the animation (stage 4) and, from stage 5, the textures and
meshes with Open Cloud.

    python upload_frost_jab_assets.py            (system Python, standard library only)
Key: ROBLOX_OPEN_CLOUD_KEY in Game/.env (git-ignored). The creator is the key's owner (read from
the key itself), which must be the game's owner so the animation is allowed to play.

    frost_jab_punch.rbxmx -> assetType Animation (a KeyframeSequence, from export_frost_jab_anim.py)
    textures (PNG)        -> assetType Image  (build_frost_jab_textures.py)
    meshes (FBX)          -> assetType Model  (a Model holding one MeshPart; Studio reads its MeshId;
                             build_frost_jab_meshes.py)
Keys "frost_ring" (texture) and "frost_ring" (mesh) would clash, so a mesh's key is "<name>.fbx".

Results go to Game/assets/vfx/frost_jab_assets.json, keyed by file with its SHA-256: a file that is
already uploaded with the same content is skipped, so rerunning never makes duplicates.
"""
import hashlib, json, os, sys, time, uuid, urllib.request, urllib.error

GAME = r"C:\Roblox\Spin for ability\Game"
ENV = os.path.join(GAME, ".env")
RESULTS = os.path.join(GAME, "assets", "vfx", "frost_jab_assets.json")
API = "https://apis.roblox.com"
TEX = os.path.join(GAME, "assets", "vfx", "textures")
FILES = [  # (key, path, assetType, content type, display name)
    ("frost_jab_punch", os.path.join(GAME, "assets", "frost_jab_punch.rbxmx"), "Animation", "model/x-rbxm",
     "FrostJab Punch"),
    *[(n, os.path.join(TEX, n + ".png"), "Image", "image/png", f"FrostJab {n}") for n in
      ("frost_flare", "frost_snowflake", "frost_shard", "frost_ring", "frost_mist_flipbook")],
    *[(n + ".fbx", os.path.join(GAME, "assets", n + ".fbx"), "Model", "model/fbx", f"FrostJab {n}") for n in
      ("ice_shard_a", "ice_shard_b", "ice_shard_c", "ice_shard_d", "frost_ring", "frost_crown")],
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
            "description": "Spin for Abilities - Frost Jab (made in Blender)",
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
    failed += resolve_mesh_ids(key, results)
    with open(RESULTS, "w") as fh:
        json.dump(results, fh, indent=1)
    print(f"done, {failed} failed; ids in {RESULTS}")


def resolve_mesh_ids(key, results):
    """A Model upload returns the PACKAGE id; MeshParts need the mesh id inside it. Studio can't load
    the package (InsertService / GetObjects: 'not authorized'), so download it with the same key
    (Open Cloud asset delivery), un-gzip the .rbxm and read its rbxassetid:// MeshId string."""
    import gzip, re
    failed = 0
    for name, entry in results.items():
        if entry.get("assetType") != "Model" or entry.get("meshId"):
            continue
        status, info = request("GET", f"{API}/asset-delivery-api/v1/assetId/{entry['assetId']}", key)
        if status != 200 or "location" not in info:
            failed += 1
            print(f"{name:20s} mesh id FAILED: delivery HTTP {status}: {info}")
            continue
        with urllib.request.urlopen(info["location"], timeout=120) as resp:
            data = resp.read()
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        ids = sorted(set(re.findall(rb"rbxassetid://(\d+)", data)))
        if len(ids) != 1:
            failed += 1
            print(f"{name:20s} mesh id FAILED: found {ids} in the package")
            continue
        entry["meshId"] = ids[0].decode()
        print(f"{name:20s} mesh id {entry['meshId']} (package {entry['assetId']})")
    return failed


main()
