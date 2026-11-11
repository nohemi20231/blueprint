#!/usr/bin/env python3
"""Generate the GitHub Copilot plugin files from the Claude Code sources.

    python3 scripts/build-copilot.py           write the generated files under copilot/
    python3 scripts/build-copilot.py --check   exit 1 if a generated file is missing or stale

Sources (edit these):
    agents/*.md                      -> copilot/agents/*.agent.md
    skills/design-rulebook/SKILL.md  -> copilot/skills/design-rulebook/SKILL.md
    skills/blueprint/templates/*     -> copilot/skills/blueprint/templates/*
    skills/blueprint/scripts/*       -> copilot/skills/blueprint/scripts/*
    hooks/no-code-before-approval.sh -> copilot/skills/blueprint/hook/blueprint-gate.sh
    skills/blueprint/SKILL.md + copilot/skill-overrides.md -> copilot/skills/blueprint/SKILL.md

Hand-written Copilot files (not generated): copilot/README.md, plugin.json, hooks.json,
skill-overrides.md, skills/blueprint/hook/blueprint-gate.json, tests/.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "copilot"

MODELS = {
    "product-framer": "Claude Opus 5.5",
    "scout": "Claude Sonnet 5.5",
    "architecture-agent": "Claude Opus 5.5",
    "service-owner": "Claude Opus 5.5",
    "compliance-reviewer": "Claude Opus 5.5",
    "cost-analyst": "Claude Sonnet 5.5",
    "operator-advocate": "Claude Sonnet 5.5",
    "refactor-reviewer": "GPT-5.5",
    "gatekeeper": "GPT-5.5",
    "scribe": "Claude Haiku 5.5",
}

# One Copilot agent per strategy, each on a different model family.
DECOMPOSERS = [
    ("decomposer-capability", "A", "A. Business capability", "Claude Opus 5.5",
     "business capability (what the business does)"),
    ("decomposer-context", "B", "B. Bounded context / subdomain", "GPT-5.5",
     "bounded context / subdomain (where the language and rules change)"),
    ("decomposer-data", "C", "C. Data ownership & transactional consistency", "Gemini 3.8 Flash",
     "data ownership and transactional consistency (what must change atomically)"),
]

FRESH = ("**Every call starts fresh.** Copilot agents keep no memory between calls, so your files "
         "are your memory. Before anything else, read `docs/architecture/kit/RULEBOOK.md` (the "
         "shared rules; cite their IDs) and `docs/architecture/rulebook.md` if it exists, then the "
         "files named in your task. Do not rely on summaries pasted into your prompt when the file "
         "exists.")
WEB = ("**Web research:** use web search if you have it; otherwise fetch primary sources by URL. "
       "List any search you could not run, so the orchestrator can fill the gap.")


def split_frontmatter(text, path):
    match = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not match:
        sys.exit(f"{path}: no frontmatter")
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields, match.group(2)


def swap(text, old, new, path):
    if text.count(old) != 1:
        sys.exit(f"{path}: expected exactly one {old!r}, found {text.count(old)}")
    return text.replace(old, new)


def copilot_agent(name, description, model, claude_tools, body):
    tools = ["read", "search"]
    if re.search(r"\b(Write|Edit)\b", claude_tools):
        tools.append("edit")
    if "Web" in claude_tools:
        tools.append("web")
    intro, rest = body.lstrip("\n").split("\n\n", 1)
    extra = FRESH + ("\n\n" + WEB if "web" in tools else "")
    head = (f"---\nname: {name}\ndescription: {description}\nmodel: {model}\n"
            f"tools: {tools!r}\nuser-invocable: false\n---\n\n")
    return head + intro + "\n\n" + extra + "\n\n" + rest


def build_agents(files):
    for src in sorted((ROOT / "agents").glob("*.md")):
        fields, body = split_frontmatter(src.read_text(encoding="utf-8"), src)
        name = fields["name"]
        if name != "decomposer":
            files[f"agents/{name}.agent.md"] = copilot_agent(
                name, fields["description"], MODELS[name], fields["tools"], body)
            continue
        for agent, letter, title, model, phrase in DECOMPOSERS:
            text = swap(body, "You are given ONE strategy and must apply it faithfully",
                        f"Your strategy is **{title}**, and you must apply it faithfully", src)
            text = swap(text, "\n## Strategies\n",
                        f"\n## Strategies (yours is {letter})\nThe other two run as separate agents "
                        "on different model families, so agreement between you is real evidence.\n", src)
            text = swap(text, "Your strategy letter, plus file paths:", "File paths:", src)
            text = swap(text, "decomposer-<strategy letter>.md", f"decomposer-{letter}.md", src)
            description = (f"Proposes a microservice decomposition using the {phrase} strategy "
                           f"(strategy {letter}). Runs in parallel with the other decomposers, each on "
                           "a different model family; the architecture agent compares them. Writes "
                           "draft service charters, a requirement-to-owner map and a diagram. No code.")
            files[f"agents/{agent}.agent.md"] = copilot_agent(
                agent, description, model, fields["tools"], text)


def sections(body):
    """Split a skill body into (title, text) pairs on '## ' headings; the first title is ''."""
    parts = re.split(r"(?m)^## (.+)\n", body)
    out = [("", parts[0])]
    out += [(parts[i], parts[i + 1]) for i in range(1, len(parts), 2)]
    return out


def build_skill(files):
    src = ROOT / "skills/blueprint/SKILL.md"
    over = OUT / "skill-overrides.md"
    fields, body = split_frontmatter(src.read_text(encoding="utf-8"), src)
    ofields, obody = split_frontmatter(over.read_text(encoding="utf-8"), over)
    overrides = dict(sections(obody)[1:])
    version = re.search(r"\(v([\d.]+)\)", body)
    if not version:
        sys.exit(f"{src}: no (vN.N) in the title")
    body = swap(body, f"(v{version.group(1)})", f"(v{version.group(1)}, GitHub Copilot)", src)
    used, out = set(), []
    for title, text in sections(body):
        key = next((k for k in overrides if title == k or title.startswith(k + " (")), None)
        if key:
            used.add(key)
            # A full heading on the override's first line replaces the heading too.
            heading, _, rest = overrides[key].partition("\n")
            if heading.startswith("@heading "):
                title, text = heading[len("@heading "):], rest
            else:
                text = overrides[key]
            text = text.rstrip("\n") + "\n\n"
        out.append((f"## {title}\n" if title else "") + text)
    unused = set(overrides) - used
    if unused:
        sys.exit(f"{over}: no section in {src.name} matches {sorted(unused)}")
    files["skills/blueprint/SKILL.md"] = (
        f"---\nname: {fields['name']}\ndescription: {ofields['description']}\n---\n"
        + "".join(out).rstrip("\n") + "\n")


def build_copies(files):
    files["skills/design-rulebook/SKILL.md"] = (
        ROOT / "skills/design-rulebook/SKILL.md").read_text(encoding="utf-8")
    for folder in ("templates", "scripts"):
        for src in sorted((ROOT / "skills/blueprint" / folder).glob("*")):
            if src.is_file():
                files[f"skills/blueprint/{folder}/{src.name}"] = src.read_text(encoding="utf-8")
    files["skills/blueprint/hook/blueprint-gate.sh"] = (
        ROOT / "hooks/no-code-before-approval.sh").read_text(encoding="utf-8")


def main():
    check = "--check" in sys.argv[1:]
    files = {}
    build_agents(files)
    build_skill(files)
    build_copies(files)

    generated_dirs = ["agents", "skills/blueprint/templates", "skills/blueprint/scripts"]
    stale = []
    for rel, text in files.items():
        path = OUT / rel
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            stale.append(rel)
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    for folder in generated_dirs:  # a file with no source left is stale too
        for path in sorted((OUT / folder).glob("*")):
            rel = path.relative_to(OUT).as_posix()
            if path.is_file() and rel not in files:
                stale.append(rel + " (no source)")
                if not check:
                    path.unlink()
    if not check:
        gate = OUT / "skills/blueprint/hook/blueprint-gate.sh"
        gate.chmod(0o755)
        print(f"copilot/: {len(files)} generated files, {len(stale)} changed")
        return
    if stale:
        print("copilot/ is out of date; run: python3 scripts/build-copilot.py")
        for rel in stale:
            print("  " + rel)
        sys.exit(1)
    print(f"copilot/: {len(files)} generated files are up to date")


if __name__ == "__main__":
    main()
