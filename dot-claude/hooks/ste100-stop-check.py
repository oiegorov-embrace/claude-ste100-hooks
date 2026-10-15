#!/usr/bin/env python3
"""Stop hook (optional): checks Claude's last reply against the countable STE100 rules.

Checks, with no model call:
- sentence length (STE100_MAX_WORDS, default 25),
- paragraph length (STE100_MAX_SENTENCES, default 6),
- words from ste100-forbidden-words.txt (next to this script).
Code blocks, inline code, URLs and table rows are skipped.

If the reply has STE100_MIN_VIOLATIONS (default 3) or more violations, the hook blocks the stop
and Claude writes the reply again. That rewrite is the expensive part: a second full reply.
On the rewrite itself (stop_hook_active is true) the hook always lets Claude stop, so it can't loop.
"""
import json
import os
import re
import sys

MAX_WORDS = int(os.environ.get("STE100_MAX_WORDS", "25"))
MAX_SENTENCES = int(os.environ.get("STE100_MAX_SENTENCES", "6"))
MIN_VIOLATIONS = int(os.environ.get("STE100_MIN_VIOLATIONS", "3"))
MAX_LISTED = 5


def load_forbidden(path):
    words = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "->" in line:
                    bad, good = (p.strip() for p in line.split("->", 1))
                    if bad:
                        words.append((bad, good))
    except FileNotFoundError:
        pass
    return words


def prose_paragraphs(text):
    text = re.sub(r"```.*?```", "\n\n", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", "CODE", text)
    text = re.sub(r"https?://\S+", "URL", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    paragraphs = []
    for block in re.split(r"\n\s*\n", text):
        lines = []
        for line in block.splitlines():
            s = line.strip()
            if not s or s.startswith("|") or s.startswith("#") or s.startswith(">"):
                continue
            # A list item is its own unit, so close the running paragraph.
            if re.match(r"^([-*+]|\d+[.)])\s+", s):
                if lines:
                    paragraphs.append(" ".join(lines))
                    lines = []
                paragraphs.append(re.sub(r"^([-*+]|\d+[.)])\s+", "", s))
            else:
                lines.append(s)
        if lines:
            paragraphs.append(" ".join(lines))
    return paragraphs


def sentences(paragraph):
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9\"'(*])", paragraph)
    return [p.strip() for p in parts if re.search(r"[A-Za-z]", p)]


def check(text, forbidden):
    found = []
    for para in prose_paragraphs(text):
        sents = sentences(para)
        if len(sents) > MAX_SENTENCES:
            found.append(f"Paragraph has {len(sents)} sentences (max {MAX_SENTENCES}): \"{sents[0][:60]}...\"")
        for s in sents:
            n = len(re.findall(r"[A-Za-z0-9][\w'’-]*", s))
            if n > MAX_WORDS:
                found.append(f"Sentence has {n} words (max {MAX_WORDS}): \"{s[:60]}...\"")
    lowered = " ".join(prose_paragraphs(text)).lower()
    for bad, good in forbidden:
        if re.search(r"(?<!\w)" + re.escape(bad.lower()) + r"(?!\w)", lowered):
            found.append(f"Use \"{good}\", not \"{bad}\".")
    return found


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return
    text = data.get("last_assistant_message") or ""
    here = os.path.dirname(os.path.abspath(__file__))
    found = check(text, load_forbidden(os.path.join(here, "ste100-forbidden-words.txt")))
    if len(found) < MIN_VIOLATIONS:
        return
    listed = "\n".join(f"- {v}" for v in found[:MAX_LISTED])
    more = f"\n- ...and {len(found) - MAX_LISTED} more." if len(found) > MAX_LISTED else ""
    reason = (
        "Your last reply does not follow ASD-STE100. Write it again in STE100. "
        "Keep the same content, code and commands. Violations:\n" + listed + more
    )
    print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
