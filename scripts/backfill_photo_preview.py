#!/usr/bin/env python3
"""Backfill photo_preview (blur base64) untuk foto galeri lama ChatYuk.
- Foto path 'gallery/...' → download dari storage publik.
- Foto base64 langsung → decode dari DB.
- Blur + resize kecil → base64 JPEG → UPDATE user_photos.photo_preview via Management API.
"""
import os, io, json, base64, urllib.request

REF = os.environ["SUPABASE_PROJECT_REF"]
TOKEN = os.environ["SUPABASE_ACCESS_TOKEN"]
URL = os.environ["SUPABASE_URL"].rstrip("/")
BUCKET = "chat-photos"
API = f"https://api.supabase.com/v1/projects/{REF}/database/query"

from PIL import Image, ImageFilter


def sql(query):
    req = urllib.request.Request(
        API,
        data=json.dumps({"query": query}).encode(),
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "User-Agent": "curl/8.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())


def make_preview(img_bytes):
    im = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    im.thumbnail((120, 120))
    im = im.filter(ImageFilter.GaussianBlur(radius=8))
    out = io.BytesIO()
    im.save(out, format="JPEG", quality=50)
    return base64.b64encode(out.getvalue()).decode()


def fetch_bytes(photo):
    if photo.startswith("gallery/"):
        u = f"{URL}/storage/v1/object/public/{BUCKET}/{photo}"
        with urllib.request.urlopen(u) as r:
            return r.read()
    # base64 langsung
    return base64.b64decode(photo)


rows = sql("select id, photo from user_photos where photo_preview is null or photo_preview = '';")
print(f"{len(rows)} foto perlu preview")
ok = 0
for row in rows:
    pid, photo = row["id"], row["photo"]
    try:
        b = fetch_bytes(photo)
        prev = make_preview(b)
        prev_esc = prev.replace("'", "''")
        sql(f"update user_photos set photo_preview = '{prev_esc}' where id = '{pid}';")
        ok += 1
        print(f"  OK {pid} ({len(prev)} b64 chars)")
    except Exception as e:
        print(f"  FAIL {pid}: {e}")

print(f"Selesai: {ok}/{len(rows)}")
