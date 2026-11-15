"""Converts question files between the game's JSON (questions/<name>.json) and a plain-text format
that is easy to write by hand (Kazakh and English side by side). See docs/question-import.md.

    python tools/questions_txt.py export saka            > saka.txt     # current bank as text
    python tools/questions_txt.py check  new_saka.txt                    # only check, write nothing
    python tools/questions_txt.py import new_saka.txt --level saka       # replace questions/saka.json

Then run the content audit and the tests (docs/question-import.md).
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qjson  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPES = ["single_choice", "fill_blank", "matching", "chronology", "map", "image"]
VIEW = (40.75, 93.05, 39.0, 56.5)  # Same fixed map view as tools/build_map.py.
MIN_PIN_GAP = 0.05


class TxtError(Exception):
    pass


def project(lat, lon):
    west, east, south, north = VIEW
    return round((lon - west) / (east - west), 3), round((north - lat) / (north - south), 3)


def split_list(text):
    return [part.strip() for part in text.split("|")]


def marked(parts):
    """Options where the correct one starts with '*': returns (clean options, index of correct)."""
    correct = [i for i, p in enumerate(parts) if p.startswith("*")]
    clean = [p.lstrip("*").strip() for p in parts]
    return clean, correct


# ---------------------------------------------------------------- import

def parse(text, source="input"):
    """Returns (questions, errors). Blocks are separated by blank lines; '#' starts a comment."""
    questions, errors = [], []
    block, start = [], 0
    lines = text.lstrip("﻿").splitlines() + [""]
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if line.startswith("#"):
            continue
        if not line:
            if block:
                try:
                    questions.append(_block(block))
                except TxtError as error:
                    errors.append("%s, question starting at line %d: %s" % (source, start, error))
                block = []
            continue
        if not block:
            start = number
        if ":" not in line:
            errors.append("%s line %d: expected 'KEY: value', got %r" % (source, number, line))
            continue
        key, value = line.split(":", 1)
        block.append((key.strip().upper(), value.strip(), number))
    return questions, errors


def _block(block):
    fields = {}
    for key, value, number in block:
        fields.setdefault(key, []).append((value, number))
    one = lambda key: fields[key][0][0] if key in fields else None
    kind = (one("TYPE") or "single_choice").lower()
    if kind not in TYPES:
        raise TxtError("TYPE must be one of " + ", ".join(TYPES))
    for key in ["Q", "Q_EN"]:
        if not one(key):
            raise TxtError("%s (the question%s) is missing" % (key, " in English" if key == "Q_EN" else ""))
    question = {}
    if one("ID"):
        question["id"] = one("ID")
    question["type"] = kind
    difficulty = one("DIFFICULTY")
    if difficulty:
        if difficulty not in ("1", "2", "3"):
            raise TxtError("DIFFICULTY must be 1, 2 or 3")
        question["difficulty"] = int(difficulty)
    question["question"] = one("Q")
    en = {"question": one("Q_EN")}
    if kind == "fill_blank" and ("___" not in question["question"] or "___" not in en["question"]):
        raise TxtError("a fill_blank question needs ___ in Q and Q_EN")

    if kind in ("single_choice", "fill_blank", "image"):
        if kind == "image":
            if not one("IMAGE"):
                raise TxtError("IMAGE (file name in assets/images) is missing")
            question["image"] = "res://assets/images/" + one("IMAGE")
        answers, correct = marked(split_list(one("A") or ""))
        answers_en, correct_en = marked(split_list(one("A_EN") or ""))
        if len(answers) != 4 or len(correct) != 1:
            raise TxtError("A needs 4 options separated by | with exactly one marked * (correct)")
        if len(answers_en) != 4 or correct_en != correct:
            raise TxtError("A_EN needs the same 4 options in English, the same one marked *")
        question["answers"] = answers
        question["correct"] = answers[correct[0]]
        en["answers"] = answers_en
        if one("EXTRA"):
            extras = split_list(one("EXTRA"))
            extras_en = split_list(one("EXTRA_EN") or "")
            if len(extras_en) != len(extras):
                raise TxtError("EXTRA_EN must translate every EXTRA decoy")
            question["extra_answers"] = extras
            en["extra_answers"] = extras_en
    elif kind == "matching":
        pairs = [_pair(v, n) for v, n in fields.get("PAIR", [])]
        pairs_en = [_pair(v, n) for v, n in fields.get("PAIR_EN", [])]
        if not 2 <= len(pairs) <= 4 or len(pairs_en) != len(pairs):
            raise TxtError("matching needs 2-4 PAIR lines and the same number of PAIR_EN lines")
        question["pairs"] = [{"left": l, "right": r} for l, r in pairs]
        en["pairs"] = [{"left": l, "right": r} for l, r in pairs_en]
    elif kind == "chronology":
        items = [v for v, _ in fields.get("ITEM", [])]
        items_en = [v for v, _ in fields.get("ITEM_EN", [])]
        if not 3 <= len(items) <= 5 or len(items_en) != len(items):
            raise TxtError("chronology needs 3-5 ITEM lines (earliest first) and the same number of ITEM_EN lines")
        question["items"] = items
        en["items"] = items_en
    elif kind == "map":
        places = []
        for value, _ in fields.get("PLACE", []):
            parts = split_list(value)
            if len(parts) != 3:
                raise TxtError("PLACE is 'name | latitude | longitude' (mark the correct one with *)")
            try:
                places.append((parts[0], float(parts[1]), float(parts[2])))
            except ValueError:
                raise TxtError("PLACE latitude and longitude must be numbers, e.g. 42.85 | 68.30")
        names_en = [v for v, _ in fields.get("PLACE_EN", [])]
        if len(places) != 4 or len(names_en) != 4:
            raise TxtError("map needs 4 PLACE lines and 4 PLACE_EN lines")
        clean, correct = marked([p[0] for p in places])
        if len(correct) != 1:
            raise TxtError("mark exactly one PLACE as correct with *")
        locations = []
        for name, (_, lat, lon) in zip(clean, places):
            x, y = project(lat, lon)
            locations.append({"name": name, "x": x, "y": y, "lat": lat, "lon": lon})
        for i in range(4):
            for j in range(i + 1, 4):
                gap = math.dist((locations[i]["x"], locations[i]["y"]), (locations[j]["x"], locations[j]["y"]))
                if gap < MIN_PIN_GAP:
                    raise TxtError("places %s and %s are too close on the map" % (clean[i], clean[j]))
        question["correct"] = clean[correct[0]]
        question["locations"] = locations
        en["locations"] = [n.lstrip("*").strip() for n in names_en]
    if one("EXPLAIN"):
        question["explanation"] = one("EXPLAIN")
    question["en"] = en
    return question


def _pair(value, number):
    if " = " not in value:
        raise TxtError("line %d: a pair is 'left = right'" % number)
    left, right = value.split(" = ", 1)
    return left.strip(), right.strip()


def number_ids(questions, level):
    """Gives tasks without an ID the next free '<level>-NN'."""
    taken = {q["id"] for q in questions if "id" in q}
    n = 1
    for q in questions:
        if "id" not in q:
            while "%s-%02d" % (level, n) in taken:
                n += 1
            q["id"] = "%s-%02d" % (level, n)
            taken.add(q["id"])
        # Keep the usual key order: id first.
        q_items = list(q.items())
        q.clear()
        q.update([("id", dict(q_items)["id"])] + [(k, v) for k, v in q_items if k != "id"])
    return questions


# ---------------------------------------------------------------- export

def export(questions):
    out = ["# Exported from the game. One question per block; blank line between blocks.",
           "# Format: docs/question-import.md", ""]
    for q in questions:
        en = q.get("en", {})
        kind = q.get("type", "single_choice")
        out.append("ID: %s" % q.get("id", ""))
        out.append("TYPE: %s" % kind)
        if "difficulty" in q:
            out.append("DIFFICULTY: %d" % q["difficulty"])
        out.append("Q: %s" % q["question"])
        out.append("Q_EN: %s" % en.get("question", ""))
        if "image" in q:
            out.append("IMAGE: %s" % q["image"].replace("res://assets/images/", ""))
        if "answers" in q:
            star = lambda opts, i: " | ".join(("*" if k == i else "") + o for k, o in enumerate(opts))
            i = q["answers"].index(q["correct"])
            out.append("A: %s" % star(q["answers"], i))
            out.append("A_EN: %s" % star(en.get("answers", [""] * 4), i))
        if "extra_answers" in q:
            out.append("EXTRA: %s" % " | ".join(q["extra_answers"]))
            out.append("EXTRA_EN: %s" % " | ".join(en.get("extra_answers", [])))
        for i, p in enumerate(q.get("pairs", [])):
            out.append("PAIR: %s = %s" % (p["left"], p["right"]))
        for p in en.get("pairs", []):
            out.append("PAIR_EN: %s = %s" % (p["left"], p["right"]))
        for item in q.get("items", []):
            out.append("ITEM: %s" % item)
        for item in en.get("items", []):
            out.append("ITEM_EN: %s" % item)
        for loc in q.get("locations", []):
            out.append("PLACE: %s%s | %s | %s" % ("*" if loc["name"] == q["correct"] else "", loc["name"], loc["lat"], loc["lon"]))
        for name in en.get("locations", []):
            out.append("PLACE_EN: %s" % name)
        if "explanation" in q:
            out.append("EXPLAIN: %s" % q["explanation"])
        out.append("")
    return "\n".join(out)


def main(argv):
    if len(argv) < 2 or argv[0] not in ("export", "check", "import"):
        print(__doc__)
        return 2
    command = argv[0]
    if command == "export":
        bank = os.path.join(ROOT, "questions", argv[1] + ".json")
        sys.stdout.reconfigure(encoding="utf-8")
        print(export(qjson.load(bank)), end="")
        return 0
    with open(argv[1], encoding="utf-8-sig") as f:
        questions, errors = parse(f.read(), os.path.basename(argv[1]))
    for error in errors:
        print("ERROR:", error)
    if errors:
        print("%d error(s); nothing written." % len(errors))
        return 1
    level = argv[argv.index("--level") + 1] if "--level" in argv else None
    if command == "check" or level is None:
        print("%d questions read, no format errors. %s" % (len(questions), "" if command == "check" else "Add --level <name> to write."))
        return 0
    ids = [q.get("id") for q in questions if q.get("id")]
    if len(ids) != len(set(ids)):
        print("ERROR: the same ID is used twice")
        return 1
    target = os.path.join(ROOT, "questions", level + ".json")
    qjson.save(target, number_ids(questions, level))
    print("Wrote %d questions to questions/%s.json. Now run the audit and the tests (docs/question-import.md)." % (len(questions), level))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
