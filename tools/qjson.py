"""Reads and writes question files in the repository's layout (one key per line, short arrays inline)."""
import json

def _inline(value):
    return json.dumps(value, ensure_ascii=False, separators=(", ", ": "))

def dumps(questions):
    out = ["["]
    for qi, q in enumerate(questions):
        out.append("  {")
        keys = list(q.keys())
        for ki, key in enumerate(keys):
            value = q[key]
            comma = "," if ki < len(keys) - 1 else ""
            if isinstance(value, list) and value and isinstance(value[0], dict):
                out.append('    "%s": [' % key)
                for i, item in enumerate(value):
                    out.append("      " + _inline(item) + ("," if i < len(value) - 1 else ""))
                out.append("    ]" + comma)
            else:
                out.append('    "%s": %s%s' % (key, _inline(value), comma))
        out.append("  }" + ("," if qi < len(questions) - 1 else ""))
    out.append("]")
    return "\n".join(out) + "\n"

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save(path, questions):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(dumps(questions))
