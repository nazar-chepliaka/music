#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKS_JSON="$ROOT_DIR/data/tracks.json"
REGISTRY_JSON="$ROOT_DIR/data/cc0-registry.json"
AUDIO_DIR="$ROOT_DIR/assets/audio"
LYRICS_DIR="$ROOT_DIR/assets/lyrics"
IMAGES_DIR="$ROOT_DIR/assets/images"
GITIGNORE_FILE="$ROOT_DIR/.gitignore"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-nazar-chepliaka/music}"
GITHUB_GIT_FILE_LIMIT=$((100 * 1024 * 1024))

created_files=()
tmp_tracks=""
tmp_registry=""

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    for file in "${created_files[@]}"; do
      [[ -f "$file" ]] && rm -f "$file"
    done
  fi
  [[ -n "$tmp_tracks" && -f "$tmp_tracks" ]] && rm -f "$tmp_tracks"
  [[ -n "$tmp_registry" && -f "$tmp_registry" ]] && rm -f "$tmp_registry"
  return "$exit_code"
}
trap cleanup EXIT

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'TXT'
Usage:
  ./track.sh add
  ./track.sh update BEAT-0007

Compatibility:
  ./add-track.sh
TXT
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

prompt() {
  local label="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$label: " value
    printf '%s' "$value"
  fi
}

prompt_optional() {
  local label="$1"
  local value
  read -r -p "$label: " value
  printf '%s' "$value"
}

confirm_yes() {
  local label="$1"
  local value
  read -r -p "$label [y/N]: " value
  [[ "$value" == "y" || "$value" == "Y" ]]
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    die "sha256sum or shasum is required to calculate SHA-256"
  fi
}

inspect_zip_contents() {
  python3 - "$1" <<'PY'
import hashlib
import json
import posixpath
import stat
import sys
import zipfile
from pathlib import PurePosixPath

archive = sys.argv[1]
items = []

try:
    with zipfile.ZipFile(archive) as zf:
        bad_file = zf.testzip()
        if bad_file is not None:
            raise SystemExit(f"corrupted ZIP member: {bad_file}")

        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            pure = PurePosixPath(name)

            if name.startswith("/") or pure.is_absolute() or any(part == ".." for part in pure.parts):
                raise SystemExit(f"unsafe ZIP path: {info.filename}")

            normalized = posixpath.normpath(name)
            if normalized in (".", "") or normalized.startswith("../"):
                raise SystemExit(f"unsafe ZIP path: {info.filename}")

            if info.is_dir() or name.endswith("/"):
                continue

            mode = (info.external_attr >> 16) & 0o170000
            if mode and not stat.S_ISREG(mode):
                raise SystemExit(f"unsupported non-regular ZIP entry: {info.filename}")

            digest = hashlib.sha256()
            with zf.open(info) as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    digest.update(chunk)

            entry = {"file": normalized, "sha256": digest.hexdigest()}
            extension = pure.suffix[1:].upper()
            if extension:
                entry["format"] = extension
            items.append(entry)
except zipfile.BadZipFile:
    raise SystemExit("not a readable ZIP archive")

if not items:
    raise SystemExit("ZIP archive contains no regular files")

items.sort(key=lambda item: item["file"])
print(json.dumps(items, ensure_ascii=False))
PY
}

copy_new_file() {
  local source="$1"
  local dest="$2"
  local tmp="${dest}.tmp.$$"
  rm -f "$tmp"
  created_files+=("$tmp")
  cp "$source" "$tmp"
  mv "$tmp" "$dest"
  created_files+=("$dest")
}

json_query() {
  python3 - "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

mode = sys.argv[1]

def read_json(path):
    with Path(path).open(encoding="utf-8") as fh:
        return json.load(fh)

def registry_items(registry):
    for entry in registry:
        for item in entry.get("items", []):
            yield item

def versions_for(item):
    if item.get("versions"):
        return item["versions"]
    files = item.get("files", [])
    if files:
        return [{"version": 1, "release_date": item.get("release_date"), "note": None, "files": files}]
    return []

if mode == "latest-registry":
    registry = read_json(sys.argv[2])
    values = [str(entry.get("registry", "")) for entry in registry if entry.get("registry")]
    print(max(values) if values else "001")
elif mode == "next-id":
    registry = read_json(sys.argv[2])
    prefix = sys.argv[3]
    width = int(sys.argv[4])
    pattern = re.compile(rf"^{re.escape(prefix)}-(\d+)$")
    max_number = 0
    for item in registry_items(registry):
        match = pattern.match(str(item.get("id", "")))
        if match:
            max_number = max(max_number, int(match.group(1)))
    print(f"{prefix}-{max_number + 1:0{width}d}")
elif mode == "slug":
    title = sys.argv[2]
    tracks = read_json(sys.argv[3])
    translit = {
        "а":"a","б":"b","в":"v","г":"h","ґ":"g","д":"d","е":"e","є":"ie","ж":"zh","з":"z","и":"y","і":"i","ї":"i","й":"i","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u","ф":"f","х":"kh","ц":"ts","ч":"ch","ш":"sh","щ":"shch","ь":"","ю":"iu","я":"ia",
        "А":"a","Б":"b","В":"v","Г":"h","Ґ":"g","Д":"d","Е":"e","Є":"ie","Ж":"zh","З":"z","И":"y","І":"i","Ї":"i","Й":"i","К":"k","Л":"l","М":"m","Н":"n","О":"o","П":"p","Р":"r","С":"s","Т":"t","У":"u","Ф":"f","Х":"kh","Ц":"ts","Ч":"ch","Ш":"sh","Щ":"shch","Ь":"","Ю":"iu","Я":"ia",
        "'":"", "’":"", "ʼ":""
    }
    raw = "".join(translit.get(ch, ch) for ch in title).lower()
    raw = re.sub(r"[^a-z0-9]+", "-", raw).strip("-")
    base = raw or "track"
    existing = {str(track.get("slug") or track.get("id")) for track in tracks}
    slug = base
    n = 2
    while slug in existing:
        slug = f"{base}-{n}"
        n += 1
    print(slug)
elif mode == "track":
    tracks = read_json(sys.argv[2])
    track_id = sys.argv[3]
    for track in tracks:
        if track_id in {str(track.get("id")), str(track.get("cc0_item_id")), str(track.get("slug"))}:
            print(json.dumps(track, ensure_ascii=False))
            break
    else:
        raise SystemExit(f"track not found: {track_id}")
elif mode == "next-version":
    registry = read_json(sys.argv[2])
    track_id = sys.argv[3]
    for item in registry_items(registry):
        if str(item.get("id")) == track_id:
            found = versions_for(item)
            current = max([int(v.get("version", 1)) for v in found] or [0])
            print(current + 1)
            break
    else:
        raise SystemExit(f"registry item not found: {track_id}")
elif mode == "field":
    obj = json.loads(sys.argv[2])
    print(obj.get(sys.argv[3], "") or "")
else:
    raise SystemExit(f"unknown mode: {mode}")
PY
}

write_json_update() {
  python3 - "$@" <<'PY'
import json
import sys
from pathlib import Path

mode, tracks_path, registry_path, out_tracks, out_registry, payload_json = sys.argv[1:]
payload = json.loads(payload_json)

tracks_path = Path(tracks_path)
registry_path = Path(registry_path)
out_tracks = Path(out_tracks)
out_registry = Path(out_registry)

with tracks_path.open(encoding="utf-8") as fh:
    tracks = json.load(fh)
with registry_path.open(encoding="utf-8") as fh:
    registry = json.load(fh)

def registry_items():
    for entry in registry:
        for item in entry.get("items", []):
            yield entry, item

def normalize_registry_item(item, fallback_release_date=None):
    if item.get("versions"):
        item["versions"] = sorted(item["versions"], key=lambda version: int(version.get("version", 0)))
    else:
        files = item.pop("files", [])
        item["versions"] = [{
            "version": 1,
            "release_date": item.get("release_date") or fallback_release_date,
            "note": None,
            "files": files,
        }]
    item["current_version"] = max(int(version.get("version", 1)) for version in item["versions"])

def find_track(track_id):
    for track in tracks:
        if track_id in {str(track.get("id")), str(track.get("cc0_item_id")), str(track.get("slug"))}:
            return track
    return None

def find_registry_item(item_id):
    for entry, item in registry_items():
        if str(item.get("id")) == item_id:
            return entry, item
    return None, None

if mode == "add":
    track_entry = payload["track_entry"]
    new_items = payload.get("registry_items") or [payload["registry_item"]]
    registry_number = str(payload["registry_number"])

    track_ids = {str(track.get("id")) for track in tracks}
    track_slugs = {str(track.get("slug") or track.get("id")) for track in tracks}
    item_ids = {str(item.get("id")) for _, item in registry_items()}
    if track_entry["id"] in track_ids or track_entry["slug"] in track_slugs:
        raise SystemExit(f"track already exists: {track_entry['id']}")
    for item in new_items:
        if item["id"] in item_ids:
            raise SystemExit(f"registry ID already exists: {item['id']}")

    for entry in registry:
        if str(entry.get("registry")) == registry_number:
            entry.setdefault("items", []).extend(new_items)
            break
    else:
        registry.append({
            "registry": registry_number,
            "release_date": track_entry["published"],
            "declaration_status": "Чернетка / очікує юридичного оформлення",
            "declaration_url": "declaration.html",
            "items": new_items,
        })
    tracks.append(track_entry)
elif mode == "update":
    track_id = payload["track_id"]
    track = find_track(track_id)
    entry, item = find_registry_item(track_id)
    if track is None or item is None:
        raise SystemExit(f"track or registry item not found: {track_id}")

    normalize_registry_item(item, entry.get("release_date"))
    new_version = int(payload["version_entry"]["version"])
    existing_versions = {int(version.get("version", 0)) for version in item["versions"]}
    if new_version in existing_versions:
        raise SystemExit(f"version already exists: {track_id} v{new_version}")

    item["versions"].append(payload["version_entry"])
    item["versions"] = sorted(item["versions"], key=lambda version: int(version.get("version", 0)))
    item["current_version"] = new_version
    item["title"] = payload["track_patch"]["title"]
    item["public_url"] = f"tracks/?id={payload['track_patch']['slug']}"

    track.update(payload["track_patch"])
elif mode == "migrate":
    for track in tracks:
        track.setdefault("current_version", 1)
        track.setdefault("updated", track.get("published"))
    for entry, item in registry_items():
        if item.get("type") in {"suno_generated_audio", "original_lyrics"}:
            normalize_registry_item(item, entry.get("release_date"))
else:
    raise SystemExit(f"unknown mode: {mode}")

out_tracks.write_text(json.dumps(tracks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
out_registry.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

prepare_common() {
  need_cmd python3
  need_cmd cp
  need_cmd mktemp

  [[ -f "$TRACKS_JSON" ]] || die "Missing $TRACKS_JSON"
  [[ -f "$REGISTRY_JSON" ]] || die "Missing $REGISTRY_JSON"
  python3 -m json.tool "$TRACKS_JSON" >/dev/null || die "Invalid JSON: data/tracks.json"
  python3 -m json.tool "$REGISTRY_JSON" >/dev/null || die "Invalid JSON: data/cc0-registry.json"
  mkdir -p "$AUDIO_DIR" "$LYRICS_DIR" "$IMAGES_DIR"
}

version_label() {
  printf 'v%03d' "$1"
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

release_asset_url() {
  local track_id="$1"
  local version_tag="$2"
  local filename="$3"
  printf 'https://github.com/%s/releases/download/%s-%s/%s' \
    "$GITHUB_REPOSITORY" "$track_id" "$version_tag" "$filename"
}

ignore_large_archive() {
  local relative_path="$1"
  local entry="/$relative_path"

  touch "$GITIGNORE_FILE"
  if ! grep -Fqx "$entry" "$GITIGNORE_FILE"; then
    printf '\n# GitHub Release asset (over 100 MiB)\n%s\n' "$entry" >> "$GITIGNORE_FILE"
  fi
}

stems_publish_path() {
  local archive="$1"
  local relative_path="$2"
  local track_id="$3"
  local version_tag="$4"
  local size
  size="$(file_size "$archive")"

  if (( size > GITHUB_GIT_FILE_LIMIT )); then
    ignore_large_archive "$relative_path"
    release_asset_url "$track_id" "$version_tag" "${relative_path##*/}"
  else
    printf '%s' "$relative_path"
  fi
}

print_archive_contents() {
  python3 - "$1" <<'PY'
import json
import sys

for item in json.loads(sys.argv[1]):
    print(f"  {item['file']}")
PY
}

archive_count() {
  python3 - "$1" <<'PY'
import json
import sys

print(len(json.loads(sys.argv[1])))
PY
}

make_files_json() {
  python3 - "$@" <<'PY'
import json
import sys

preview_path, preview_sha, stems_path, stems_sha, stems_contents_json = sys.argv[1:]
print(json.dumps([
    {"format": "MP3", "role": "preview", "path": preview_path, "sha256": preview_sha},
    {
        "format": "STEMS",
        "container": "ZIP",
        "role": "source_package",
        "description": "Окремі доріжки / stems. Вміст архіву належить до цього самого CC0-релізу настільки, наскільки видавець має право застосувати CC0.",
        "path": stems_path,
        "sha256": stems_sha,
        "contents": json.loads(stems_contents_json),
    },
], ensure_ascii=False))
PY
}

validate_sources() {
  local preview_source="$1"
  local stems_source="$2"

  [[ -f "$preview_source" ]] || die "Preview MP3 source file does not exist: $preview_source"
  [[ "${preview_source,,}" == *.mp3 ]] || die "Preview source must have .mp3 extension"
  [[ -f "$stems_source" ]] || die "STEMS source ZIP does not exist: $stems_source"
  [[ -r "$stems_source" ]] || die "STEMS source ZIP is not readable: $stems_source"
  [[ "${stems_source,,}" == *.zip ]] || die "STEMS archive must have .zip extension"
}

run_add() {
  prepare_common

  local today latest_registry title bpm key duration preview_source stems_source lyrics_source published registry_number artwork_source
  today="$(date +%F)"
  latest_registry="$(json_query latest-registry "$REGISTRY_JSON")"

  printf 'Додати новий CC0 трек\n\n'
  title="$(prompt 'Назва')"
  [[ -n "$title" ]] || die "Track title is required"
  bpm="$(prompt_optional 'BPM')"
  [[ -z "$bpm" || "$bpm" =~ ^[0-9]+$ ]] || die "BPM must be numeric"
  key="$(prompt_optional 'Тональність')"
  duration="$(prompt_optional 'Тривалість (MM:SS або H:MM:SS)')"
  [[ -z "$duration" || "$duration" =~ ^([0-9]+:)?[0-5]?[0-9]:[0-5][0-9]$ ]] || die "Duration must look like MM:SS or H:MM:SS"
  preview_source="$(prompt 'MP3 для прослуховування')"
  stems_source="$(prompt 'Архів STEMS')"
  lyrics_source="$(prompt_optional 'Текст (необов’язково)')"
  published="$(prompt 'Дата публікації' "$today")"
  registry_number="$(prompt 'Номер реєстру' "$latest_registry")"
  artwork_source="$(prompt_optional 'Обкладинка (необов’язково)')"

  [[ "$published" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Publication date must be YYYY-MM-DD"
  [[ "$registry_number" =~ ^[0-9]+$ ]] || die "Registry number must be numeric"
  registry_number="$(printf '%03d' "$((10#$registry_number))")"
  validate_sources "$preview_source" "$stems_source"
  local stems_contents_json
  stems_contents_json="$(inspect_zip_contents "$stems_source")" || die "Invalid STEMS ZIP archive"

  local lyrics_original lyrics_id image_id
  lyrics_original="no"
  lyrics_id=""
  image_id=""
  if [[ -n "$lyrics_source" ]]; then
    [[ -f "$lyrics_source" ]] || die "Lyrics source file does not exist: $lyrics_source"
    [[ "${lyrics_source,,}" == *.txt ]] || die "Lyrics source must have .txt extension"
    if confirm_yes 'Чи це оригінальний текст, створений видавцем?'; then
      lyrics_original="yes"
    fi
    [[ "$lyrics_original" == "yes" ]] || die "Lyrics can only be published when explicitly confirmed as original text created by the publisher"
    lyrics_id="$(json_query next-id "$REGISTRY_JSON" LYR 4)"
  fi
  if [[ -n "$artwork_source" ]]; then
    [[ -f "$artwork_source" ]] || die "Artwork source file does not exist: $artwork_source"
    case "${artwork_source,,}" in
      *.jpg|*.jpeg|*.png|*.webp|*.svg) ;;
      *) die "Artwork must be .jpg, .jpeg, .png, .webp, or .svg" ;;
    esac
    image_id="$(json_query next-id "$REGISTRY_JSON" IMG 4)"
  fi

  local track_id slug version version_tag preview_dest_rel stems_dest_rel preview_dest stems_dest
  track_id="$(json_query next-id "$REGISTRY_JSON" BEAT 4)"
  slug="$(json_query slug "$title" "$TRACKS_JSON")"
  version=1
  version_tag="$(version_label "$version")"
  preview_dest_rel="assets/audio/${track_id}-${version_tag}-${slug}-preview.mp3"
  stems_dest_rel="assets/audio/${track_id}-${version_tag}-${slug}-stems.zip"
  preview_dest="$ROOT_DIR/$preview_dest_rel"
  stems_dest="$ROOT_DIR/$stems_dest_rel"

  local lyrics_dest_rel lyrics_dest artwork_dest_rel artwork_dest
  lyrics_dest_rel=""
  lyrics_dest=""
  if [[ -n "$lyrics_source" ]]; then
    lyrics_dest_rel="assets/lyrics/${lyrics_id}-${slug}.txt"
    lyrics_dest="$ROOT_DIR/$lyrics_dest_rel"
  fi
  artwork_dest_rel="assets/images/site-artwork.jpg"
  artwork_dest=""
  if [[ -n "$artwork_source" ]]; then
    local artwork_ext
    artwork_ext="${artwork_source##*.}"
    artwork_ext="${artwork_ext,,}"
    [[ "$artwork_ext" == "jpeg" ]] && artwork_ext="jpg"
    artwork_dest_rel="assets/images/${image_id}-${slug}.${artwork_ext}"
    artwork_dest="$ROOT_DIR/$artwork_dest_rel"
  fi

  for dest in "$preview_dest" "$stems_dest" "$lyrics_dest" "$artwork_dest"; do
    [[ -z "$dest" ]] && continue
    [[ ! -e "$dest" ]] || die "Destination already exists: ${dest#$ROOT_DIR/}"
  done

  printf '\nTrack:\n  %s\n  %s\n' "$track_id" "$title"
  [[ -n "$bpm" ]] && printf '  %s BPM\n' "$bpm"
  [[ -n "$key" ]] && printf '  %s\n' "$key"
  [[ -n "$duration" ]] && printf '  %s\n' "$duration"
  printf '  Version: %s\n  Slug: %s\n' "$version" "$slug"
  printf '\nPreview:\n  %s\n\nSource package:\n  %s\n\nArchive contents:\n' "$preview_dest_rel" "$stems_dest_rel"
  print_archive_contents "$stems_contents_json"
  printf '\nFiles inside archive: %s\n' "$(archive_count "$stems_contents_json")"
  [[ -n "$lyrics_dest_rel" ]] && printf '\nLyrics:\n  %s\n' "$lyrics_id"
  [[ -n "$artwork_dest" ]] && printf '\nArtwork:\n  %s\n' "$artwork_dest_rel"
  printf '\nCC0 Registry:\n  №%s\n\n' "$registry_number"

  if ! confirm_yes 'Опублікувати трек?'; then
    printf 'Cancelled. No files changed.\n'
    exit 0
  fi

  copy_new_file "$preview_source" "$preview_dest"
  copy_new_file "$stems_source" "$stems_dest"
  [[ -n "$lyrics_source" ]] && copy_new_file "$lyrics_source" "$lyrics_dest"
  [[ -n "$artwork_source" ]] && copy_new_file "$artwork_source" "$artwork_dest"

  local preview_sha stems_sha stems_public_path lyrics_sha artwork_sha files_json payload
  preview_sha="$(sha256_file "$preview_dest")"
  stems_sha="$(sha256_file "$stems_dest")"
  stems_public_path="$(stems_publish_path "$stems_dest" "$stems_dest_rel" "$track_id" "$version_tag")"
  lyrics_sha=""
  artwork_sha=""
  [[ -n "$lyrics_dest" ]] && lyrics_sha="$(sha256_file "$lyrics_dest")"
  [[ -n "$artwork_dest" ]] && artwork_sha="$(sha256_file "$artwork_dest")"
  files_json="$(make_files_json "$preview_dest_rel" "$preview_sha" "$stems_public_path" "$stems_sha" "$stems_contents_json")"

  payload="$(python3 - "$track_id" "$slug" "$registry_number" "$title" "$bpm" "$key" "$duration" "$published" "$preview_dest_rel" "$stems_public_path" "$lyrics_id" "$lyrics_dest_rel" "$lyrics_sha" "$image_id" "$artwork_dest_rel" "$artwork_sha" "$files_json" <<'PY'
import json
import sys

(
    track_id, slug, registry, title, bpm, key, duration, published, preview,
    stems, lyrics_id, lyrics_path, lyrics_sha, image_id, cover, image_sha, files_json
) = sys.argv[1:]
track_entry = {
    "id": track_id,
    "title": title,
    "slug": slug,
    "current_version": 1,
    "bpm": int(bpm) if bpm else None,
    "key": key,
    "duration": duration,
    "published": published,
    "updated": published,
    "registry": registry,
    "source": "suno",
    "preview": preview,
    "stems": stems,
    "full_mix": None,
    "lyrics_id": lyrics_id or None,
    "cc0_item_id": track_id,
    "cover": cover,
    "license": "CC0",
    "suno_generated": True,
    "origin_note": "Аудіо згенеровано за допомогою Suno.",
    "description": f"{title} — музичний трек, опублікований під CC0 1.0 Universal.",
}
registry_item = {
    "id": track_id,
    "title": title,
    "type": "suno_generated_audio",
    "origin_label": "AI-generated with Suno",
    "public_url": f"tracks/?id={slug}",
    "current_version": 1,
    "versions": [{
        "version": 1,
        "release_date": published,
        "note": None,
        "files": json.loads(files_json),
    }],
}
registry_items = [registry_item]
if lyrics_id:
    registry_items.append({
        "id": lyrics_id,
        "title": title,
        "type": "original_lyrics",
        "origin_label": "Оригінальний текст",
        "author_declaration": "Заявлено як створений видавцем проєкту",
        "public_url": "",
        "current_version": 1,
        "versions": [{
            "version": 1,
            "release_date": published,
            "note": None,
            "files": [{"format": "TXT", "path": lyrics_path, "sha256": lyrics_sha}],
        }],
    })
if image_id:
    registry_items.append({
        "id": image_id,
        "title": f"{title} artwork",
        "type": "image",
        "origin_label": "Зображення надане видавцем проєкту",
        "public_url": f"tracks/?id={slug}",
        "files": [{"format": cover.rsplit(".", 1)[-1].upper(), "path": cover, "sha256": image_sha}],
    })
print(json.dumps({"registry_number": registry, "track_entry": track_entry, "registry_items": registry_items}, ensure_ascii=False))
PY
)"

  tmp_tracks="$(mktemp)"
  tmp_registry="$(mktemp)"
  write_json_update add "$TRACKS_JSON" "$REGISTRY_JSON" "$tmp_tracks" "$tmp_registry" "$payload"
  mv "$tmp_tracks" "$TRACKS_JSON"
  tmp_tracks=""
  mv "$tmp_registry" "$REGISTRY_JSON"
  tmp_registry=""

  printf '\n✓ Track added: %s v001\n' "$track_id"
  if [[ "$stems_public_path" == https://* ]]; then
    printf '  Upload the ignored local archive to GitHub Release tag %s-%s:\n  %s\n' \
      "$track_id" "$version_tag" "$stems_dest"
  fi
}

run_update() {
  prepare_common
  local track_id="$1"
  [[ "$track_id" =~ ^BEAT-[0-9]+$ ]] || die "Use a stable BEAT ID, for example BEAT-0007"

  local track_json title slug current_version new_version today
  track_json="$(json_query track "$TRACKS_JSON" "$track_id")"
  title="$(json_query field "$track_json" title)"
  slug="$(json_query field "$track_json" slug)"
  [[ -n "$slug" ]] || slug="$(json_query field "$track_json" id)"
  current_version="$(json_query field "$track_json" current_version)"
  [[ -n "$current_version" ]] || current_version=1
  new_version="$(json_query next-version "$REGISTRY_JSON" "$track_id")"
  today="$(date +%F)"

  printf 'Оновлення треку\n\nID:\n%s\n\nНазва:\n%s\n\nПоточна версія:\n%s\n\nБуде створено:\nversion %s\n\n' "$track_id" "$title" "$current_version" "$new_version"

  local preview_source stems_source new_title bpm key duration lyrics_id version_note published
  preview_source="$(prompt 'Новий MP3 для прослуховування')"
  stems_source="$(prompt 'Новий архів STEMS')"
  new_title="$(prompt 'Оновлена назва' "$title")"
  bpm="$(prompt 'Оновлений BPM' "$(json_query field "$track_json" bpm)")"
  [[ -z "$bpm" || "$bpm" =~ ^[0-9]+$ ]] || die "BPM must be numeric"
  key="$(prompt 'Оновлена тональність' "$(json_query field "$track_json" key)")"
  duration="$(prompt 'Оновлена тривалість' "$(json_query field "$track_json" duration)")"
  [[ -z "$duration" || "$duration" =~ ^([0-9]+:)?[0-5]?[0-9]:[0-5][0-9]$ ]] || die "Duration must look like MM:SS or H:MM:SS"
  lyrics_id="$(prompt 'lyrics_id' "$(json_query field "$track_json" lyrics_id)")"
  version_note="$(prompt_optional 'Version note (необов’язково)')"
  published="$(prompt 'Дата публікації версії' "$today")"
  [[ "$published" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Publication date must be YYYY-MM-DD"

  validate_sources "$preview_source" "$stems_source"
  local stems_contents_json
  stems_contents_json="$(inspect_zip_contents "$stems_source")" || die "Invalid STEMS ZIP archive"

  local version_tag preview_dest_rel stems_dest_rel preview_dest stems_dest
  version_tag="$(version_label "$new_version")"
  preview_dest_rel="assets/audio/${track_id}-${version_tag}-${slug}-preview.mp3"
  stems_dest_rel="assets/audio/${track_id}-${version_tag}-${slug}-stems.zip"
  preview_dest="$ROOT_DIR/$preview_dest_rel"
  stems_dest="$ROOT_DIR/$stems_dest_rel"
  [[ ! -e "$preview_dest" ]] || die "Destination already exists: $preview_dest_rel"
  [[ ! -e "$stems_dest" ]] || die "Destination already exists: $stems_dest_rel"

  printf '\nОновлення:\n\n%s\n%s\n\nПоточна версія:\n%s\n\nНова версія:\n%s\n\nPreview:\n%s\n\nSTEMS:\n%s\n\nVersion note:\n%s\n\nArchive files:\n%s\n\n' \
    "$track_id" "$new_title" "$current_version" "$new_version" "$preview_dest_rel" "$stems_dest_rel" "${version_note:-—}" "$(archive_count "$stems_contents_json")"

  if ! confirm_yes "Опублікувати version $new_version?"; then
    printf 'Cancelled. No files changed.\n'
    exit 0
  fi

  copy_new_file "$preview_source" "$preview_dest"
  copy_new_file "$stems_source" "$stems_dest"

  local preview_sha stems_sha stems_public_path files_json payload
  preview_sha="$(sha256_file "$preview_dest")"
  stems_sha="$(sha256_file "$stems_dest")"
  stems_public_path="$(stems_publish_path "$stems_dest" "$stems_dest_rel" "$track_id" "$version_tag")"
  files_json="$(make_files_json "$preview_dest_rel" "$preview_sha" "$stems_public_path" "$stems_sha" "$stems_contents_json")"

  payload="$(python3 - "$track_id" "$new_version" "$new_title" "$slug" "$bpm" "$key" "$duration" "$published" "$preview_dest_rel" "$stems_public_path" "$lyrics_id" "$files_json" "$version_note" <<'PY'
import json
import sys

track_id, version, title, slug, bpm, key, duration, release_date, preview, stems, lyrics_id, files_json, note = sys.argv[1:]
track_patch = {
    "id": track_id,
    "cc0_item_id": track_id,
    "title": title,
    "slug": slug,
    "current_version": int(version),
    "bpm": int(bpm) if bpm else None,
    "key": key,
    "duration": duration,
    "updated": release_date,
    "preview": preview,
    "stems": stems,
    "full_mix": None,
    "lyrics_id": lyrics_id or None,
    "description": f"{title} — музичний трек, опублікований під CC0 1.0 Universal.",
}
version_entry = {
    "version": int(version),
    "release_date": release_date,
    "note": note or None,
    "files": json.loads(files_json),
}
print(json.dumps({"track_id": track_id, "track_patch": track_patch, "version_entry": version_entry}, ensure_ascii=False))
PY
)"

  tmp_tracks="$(mktemp)"
  tmp_registry="$(mktemp)"
  write_json_update update "$TRACKS_JSON" "$REGISTRY_JSON" "$tmp_tracks" "$tmp_registry" "$payload"
  mv "$tmp_tracks" "$TRACKS_JSON"
  tmp_tracks=""
  mv "$tmp_registry" "$REGISTRY_JSON"
  tmp_registry=""

  printf '\n✓ Track updated: %s %s\n' "$track_id" "$version_tag"
  if [[ "$stems_public_path" == https://* ]]; then
    printf '  Upload the ignored local archive to GitHub Release tag %s-%s:\n  %s\n' \
      "$track_id" "$version_tag" "$stems_dest"
  fi
}

run_migrate() {
  prepare_common
  tmp_tracks="$(mktemp)"
  tmp_registry="$(mktemp)"
  write_json_update migrate "$TRACKS_JSON" "$REGISTRY_JSON" "$tmp_tracks" "$tmp_registry" '{}'
  mv "$tmp_tracks" "$TRACKS_JSON"
  tmp_tracks=""
  mv "$tmp_registry" "$REGISTRY_JSON"
  tmp_registry=""
  printf '✓ Existing tracks migrated to explicit version metadata\n'
}

command="${1:-}"
case "$command" in
  add)
    shift
    [[ $# -eq 0 ]] || die "add does not accept arguments"
    run_add
    ;;
  update)
    shift
    [[ $# -eq 1 ]] || die "update requires exactly one BEAT ID"
    run_update "$1"
    ;;
  migrate)
    shift
    [[ $# -eq 0 ]] || die "migrate does not accept arguments"
    run_migrate
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    die "unknown command: $command"
    ;;
esac
