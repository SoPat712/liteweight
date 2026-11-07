#!/usr/bin/env python3
"""Build text-only OpenGym exercise updates for liteweight's library and Hevy matching.

The converter intentionally reads only catalogue JSON. It does not copy or inspect
OpenGym media. Existing liteweight records are matched by their legacy media filename
prefixes (and generated negative IDs), so historical UUIDs and artwork references
remain stable in the generated template metadata.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


NAMESPACE = bytes.fromhex("6f96f4ec5d984cc3bdf9956e77c36681")
MEDIA_PREFIX_RE = re.compile(r"^(\d+)-")
LOWERCASE_TITLE_WORDS = {"and", "or", "to", "with", "on", "in"}


class ConversionError(ValueError):
    """Raised when source or existing-catalogue integrity is unsafe to convert."""


def stable_uuid(name: str) -> str:
    """Return the same RFC 4122 v5 UUID as generate_exercise_catalog.mjs."""

    digest = bytearray(hashlib.sha1(NAMESPACE + name.encode("utf-8")).digest()[:16])
    digest[6] = (digest[6] & 0x0F) | 0x50
    digest[8] = (digest[8] & 0x3F) | 0x80
    hex_value = bytes(digest).hex().upper()
    return (
        f"{hex_value[0:8]}-{hex_value[8:12]}-{hex_value[12:16]}-"
        f"{hex_value[16:20]}-{hex_value[20:32]}"
    )


def title_case(value: str) -> str:
    """Mirror the generator's titleCase helper for source exercise names."""

    words = value.split(" ")
    output: list[str] = []
    for index, word in enumerate(words):
        lower = word.lower()
        if lower == "ez":
            output.append("EZ")
        elif lower == "sldl":
            output.append("SLDL")
        elif index > 0 and lower in LOWERCASE_TITLE_WORDS:
            output.append(lower)
        elif word:
            output.append(word[0].upper() + word[1:])
        else:
            output.append(word)
    return " ".join(output)


def unique(values: list[Any]) -> list[Any]:
    """Deduplicate JSON scalar values while retaining source order."""

    result: list[Any] = []
    for value in values:
        if value is None or value == "":
            continue
        if value not in result:
            result.append(value)
    return result


def string_list(value: Any, *, field: str, source_id: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ConversionError(f"source {source_id}: {field} must be an array of strings")
    return value[:]


def source_files(source_root: Path) -> list[Path]:
    exercise_root = source_root / "exercises" if (source_root / "exercises").is_dir() else source_root
    if not exercise_root.is_dir():
        raise ConversionError(f"source catalogue directory does not exist: {exercise_root}")
    files = sorted(path for path in exercise_root.glob("*.json") if path.is_file())
    if not files:
        raise ConversionError(f"no exercise JSON files found in {exercise_root}")
    return files


def read_source(source_root: Path) -> list[dict[str, Any]]:
    all_ids: dict[str, Path] = {}
    canonical: list[dict[str, Any]] = []
    canonical_ids: set[str] = set()

    for path in source_files(source_root):
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ConversionError(f"could not read source JSON {path}: {error}") from error
        if not isinstance(value, dict):
            raise ConversionError(f"source JSON {path} must contain one object")
        source_id = value.get("id")
        if not isinstance(source_id, str) or not source_id or not source_id.isdigit():
            raise ConversionError(f"source JSON {path}: id must be a numeric string")
        if source_id in all_ids:
            raise ConversionError(f"duplicate OpenGym source id {source_id}: {all_ids[source_id]} and {path}")
        all_ids[source_id] = path
        if "variantOf" in value:
            continue
        if source_id in canonical_ids:
            raise ConversionError(f"duplicate canonical OpenGym source id {source_id}")
        canonical_ids.add(source_id)
        if not isinstance(value.get("name"), str) or not value["name"].strip():
            raise ConversionError(f"source {source_id}: canonical record is missing name")
        canonical.append(value)

    canonical.sort(key=lambda item: (int(item["id"]), item["id"]))
    return canonical


def read_existing(path: Path) -> list[dict[str, Any]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConversionError(f"could not read existing catalogue {path}: {error}") from error
    if not isinstance(value, list):
        raise ConversionError(f"existing catalogue {path} must contain an array")

    ids: dict[int, dict[str, Any]] = {}
    uuids: dict[str, dict[str, Any]] = {}
    for index, exercise in enumerate(value):
        if not isinstance(exercise, dict):
            raise ConversionError(f"existing catalogue entry {index} must be an object")
        exercise_id = exercise.get("id")
        uuid = exercise.get("uuid")
        if not isinstance(exercise_id, int) or isinstance(exercise_id, bool):
            raise ConversionError(f"existing catalogue entry {index}: id must be an integer")
        if not isinstance(uuid, str) or not uuid:
            raise ConversionError(f"existing catalogue entry {index}: uuid must be a non-empty string")
        if exercise_id in ids:
            raise ConversionError(f"existing catalogue duplicate id {exercise_id}")
        if uuid in uuids:
            raise ConversionError(f"existing catalogue duplicate uuid {uuid}")
        aliases = exercise.get("alias", [])
        if not isinstance(aliases, list) or any(not isinstance(alias, str) for alias in aliases):
            raise ConversionError(f"existing catalogue entry {index}: alias must be an array of strings")
        ids[exercise_id] = exercise
        uuids[uuid] = exercise
    return value


def media_prefix(value: Any, *, field: str, exercise_id: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise ConversionError(f"existing id {exercise_id}: {field} must be a string or null")
    basename = value.rsplit("/", 1)[-1]
    match = MEDIA_PREFIX_RE.match(basename)
    if match is None:
        raise ConversionError(f"existing id {exercise_id}: {field} has no numeric source prefix: {value}")
    return match.group(1)


def bind_match(
    matches: dict[str, dict[str, Any]], source_id: str, exercise: dict[str, Any], *, reason: str
) -> None:
    prior = matches.get(source_id)
    if prior is None:
        matches[source_id] = exercise
        return
    if prior.get("uuid") != exercise.get("uuid") or prior.get("id") != exercise.get("id"):
        raise ConversionError(
            f"OpenGym source id {source_id} collides while matching {reason}: "
            f"existing {prior.get('id')}/{prior.get('uuid')} vs {exercise.get('id')}/{exercise.get('uuid')}"
        )


def existing_matches(
    canonical: list[dict[str, Any]], existing: list[dict[str, Any]]
) -> tuple[dict[str, dict[str, Any]], int]:
    source_ids = {exercise["id"] for exercise in canonical}
    source_ids_by_number: dict[int, list[str]] = {}
    for source_id in source_ids:
        source_ids_by_number.setdefault(int(source_id), []).append(source_id)
    for ids in source_ids_by_number.values():
        if len(ids) > 1:
            raise ConversionError(f"numeric OpenGym IDs collide after parsing: {ids}")

    matches: dict[str, dict[str, Any]] = {}
    media_prefixes: set[str] = set()
    for exercise in existing:
        prefixes: set[str] = set()
        for field in ("image", "animation"):
            prefix = media_prefix(exercise.get(field), field=field, exercise_id=exercise["id"])
            if prefix is not None:
                prefixes.add(prefix)
        for prefix in prefixes:
            if prefix not in source_ids:
                raise ConversionError(
                    f"existing id {exercise['id']} media prefix {prefix} is not a canonical OpenGym source id"
                )
            media_prefixes.add(prefix)
            bind_match(matches, prefix, exercise, reason="legacy media prefix")

    for exercise in existing:
        exercise_id = exercise["id"]
        if exercise_id >= 0:
            continue
        numeric_source_id = -exercise_id - 1
        candidate_ids = source_ids_by_number.get(numeric_source_id, [])
        if len(candidate_ids) != 1:
            raise ConversionError(
                f"existing generated id {exercise_id} does not resolve to one canonical OpenGym source id"
            )
        bind_match(matches, candidate_ids[0], exercise, reason="generated negative id")

    return matches, len(media_prefixes)


def template_for(
    source: dict[str, Any], existing: dict[str, Any] | None
) -> dict[str, Any]:
    source_id = source["id"]
    source_name = source["name"].strip()
    title = title_case(source_name)
    target = source.get("target") or source.get("bodyPart")
    if target is not None and not isinstance(target, str):
        raise ConversionError(f"source {source_id}: target/bodyPart must be a string")
    primary = unique([target])
    secondary = [
        muscle
        for muscle in unique(string_list(source.get("secondaryMuscles"), field="secondaryMuscles", source_id=source_id))
        if muscle not in primary
    ]
    equipment = source.get("equipment")
    if equipment is not None and not isinstance(equipment, str):
        raise ConversionError(f"source {source_id}: equipment must be a string")
    instructions = string_list(source.get("instructions"), field="instructions", source_id=source_id)
    description = source.get("description")
    if description is not None and not isinstance(description, str):
        raise ConversionError(f"source {source_id}: description must be a string")

    aliases: list[str] = []
    if existing is not None:
        aliases.extend(existing.get("alias", []))
        aliases.append(existing.get("title"))
    aliases.extend([source_name, title])

    if existing is None:
        exercise_uuid = stable_uuid(f"opengym:{source_id}")
        exercise_id = -(int(source_id) + 1)
        pdf: list[Any] = []
        image = None
        animation = None
    else:
        exercise_uuid = existing["uuid"]
        exercise_id = existing["id"]
        pdf = existing.get("pdf", [])
        image = existing.get("image")
        animation = existing.get("animation")

    return {
        "uuid": exercise_uuid,
        "id": exercise_id,
        "title": title,
        "alias": unique(aliases),
        "primer": description,
        "primary": primary,
        "secondary": secondary,
        "equipment": unique([equipment]),
        "steps": instructions,
        "tips": [],
        "references": [],
        "pdf": pdf,
        "image": image,
        "animation": animation,
        "opengymID": source_id,
    }


def validate_templates(templates: list[dict[str, Any]], source_ids: set[str]) -> None:
    if len(templates) != len(source_ids):
        raise ConversionError(f"generated {len(templates)} templates for {len(source_ids)} source IDs")
    ids = [template["id"] for template in templates]
    uuids = [template["uuid"] for template in templates]
    opengym_ids = [template["opengymID"] for template in templates]
    if len(set(ids)) != len(ids):
        raise ConversionError("generated templates contain duplicate numeric IDs")
    if len(set(uuids)) != len(uuids):
        raise ConversionError("generated templates contain duplicate UUIDs")
    if set(opengym_ids) != source_ids:
        raise ConversionError("generated templates do not cover exactly the canonical source IDs")


def validate_against_existing(
    templates: list[dict[str, Any]], existing: list[dict[str, Any]], matches: dict[str, dict[str, Any]]
) -> None:
    """Reject new IDs/UUIDs that would collide with any retained liteweight record."""

    existing_ids = {exercise["id"] for exercise in existing}
    existing_uuids = {exercise["uuid"] for exercise in existing}
    for template in templates:
        if template["opengymID"] in matches:
            continue
        if template["id"] in existing_ids:
            raise ConversionError(
                f"new OpenGym source id {template['opengymID']} reuses existing numeric id {template['id']}"
            )
        if template["uuid"] in existing_uuids:
            raise ConversionError(
                f"new OpenGym source id {template['opengymID']} reuses existing UUID {template['uuid']}"
            )


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="OpenGym catalogue root or exercises directory")
    parser.add_argument("--existing", required=True, type=Path, help="Existing liteweight exercises.json")
    parser.add_argument("--output", required=True, type=Path, help="Generated text-template JSON path")
    parser.add_argument("--id-map", required=True, type=Path, help="Generated OpenGym source-id to UUID JSON path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        canonical = read_source(args.source)
        existing = read_existing(args.existing)
        matches, media_prefix_count = existing_matches(canonical, existing)
        source_ids = {exercise["id"] for exercise in canonical}

        templates = [template_for(source, matches.get(source["id"])) for source in canonical]
        validate_templates(templates, source_ids)
        validate_against_existing(templates, existing, matches)

        id_map = {template["opengymID"]: template["uuid"] for template in templates}
        if len(id_map) != len(templates):
            raise ConversionError("generated source-id map contains duplicate IDs")
        write_json(args.output, templates)
        write_json(args.id_map, dict(sorted(id_map.items(), key=lambda item: (int(item[0]), item[0]))))
    except ConversionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    matched = len(matches)
    generated = len(templates) - matched
    print(
        f"Generated {len(templates)} OpenGym text templates "
        f"({matched} existing UUID/media matches, {generated} stable new IDs, "
        f"{media_prefix_count} unique existing media prefixes)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
