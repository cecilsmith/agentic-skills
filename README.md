# agentic-skills

A curated collection of [Agent Skills](https://agentskills.io) — portable,
version-controlled instructions that extend an AI coding agent with domain
knowledge it does not have.

Each skill is a directory with a `SKILL.md` plus the reference material and
scripts it needs. The format is provider-neutral: the same directory works in
Claude Code, in Codex, and in anything else implementing the standard.

Many of these are bits and pieces (in part or whole) of skills that others have produced. Inspiration comes from: [pstack](https://github.com/cursor/plugins/tree/main/pstack) and others.

## Skills

| Skill                              | What it covers                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [`kicad`](skills/kicad/SKILL.md)   | KiCad file formats, symbol/footprint libraries, `kicad-cli`, schematic and layout review, fabrication output |
| [`technical-writing`](skills/technical-writing/SKILL.md) | Write technical text following best practices. Used for writing or reviewing docs, RFCs, readmes, PR descriptions, or commit messages |
| [`unslop`](skills/unslop/SKILL.md) | Edit text to remove AI patterns and add human voice.                                                         |
| [`typesafe-ai`](skills/typesafe-ai/SKILL.md) | Add support for building with TypeSafe-AI's Jev agent | 

## Install

### Claude Code (recommended)

```bash
/plugin marketplace add cecilsmith/agentic-skills
```

then install the `agentic-skills` plugin. Updates arrive with the marketplace,
and skills appear namespaced as `/agentic-skills:kicad`.

### Any agent — symlinks

Clone once, link everywhere. One canonical copy; `git pull` updates every agent
at the same time.

```bash
git clone https://github.com/cecilsmith/agentic-skills.git
cd agentic-skills
./scripts/install.sh
```

The installer links each skill individually into every skill directory it
detects — `~/.claude/skills` for Claude Code, `~/.agents/skills` for the Agent
Skills standard. It never replaces a directory it did not create.

```bash
./scripts/install.sh --dry-run       # show what would happen
./scripts/install.sh kicad           # one skill only
./scripts/install.sh --list          # show current link state
./scripts/install.sh --target DIR    # link somewhere else as well
./scripts/install.sh --uninstall     # remove this repo's links
```

Project-scoped instead of global: symlink into `.claude/skills/` inside the
project, or add the plugin to that project's settings.

## Layout

```
agentic-skills/
├── .claude-plugin/
│   ├── marketplace.json    # makes the repo installable in one command
│   └── plugin.json         # the repo is both the marketplace and the plugin
├── skills/
│   └── <skill_name>/
│       ├── SKILL.md        # router: when to use, rules, pointers
│       ├── references/     # detail, loaded only when the task reaches it
│       └── scripts/        # executable tooling
├── template/SKILL.md
└── scripts/
    └── install.sh
```

`skills/` is flat and provider-independent on purpose:

- **Flat.** Discovery is `<skills-root>/<name>/SKILL.md`. Grouping skills into
  category directories changes how they are found and makes the category part of
  the skill's identity. Taxonomy belongs in the table above, not in the tree.
- **Provider-independent.** No `SKILL.md` says "when using Claude, do X." If an
  agent ever needs different handling, that goes in an adapter beside the skill,
  never inside it.

## Writing a skill

Copy `template/SKILL.md` into `skills/<name>/` and fill it in.

**The description is the whole trigger surface.** It is the only part of a skill
that is always in context; everything else loads after the agent has already
decided the skill is relevant. Write it with the concrete nouns, file
extensions, and tool names a request would actually contain, and say when to use
it:

```yaml
---
name: kicad
description: >-
  Design, review, edit, and produce fabrication outputs for KiCad projects.
  Use when working with .kicad_sch, .kicad_pcb, .kicad_pro, .kicad_mod, or
  .kicad_sym files; running ERC or DRC; ...
---
```

**Keep `SKILL.md` a router.** It states scope, the rules that must not be broken,
and a table pointing at `references/`. Detail lives in the references so it costs
nothing until it is needed — that is the whole point of the format, and it is
what makes a collection of fifty skills viable.

**Stay on the six spec fields** — `name`, `description`, `license`,
`compatibility`, `metadata`, `allowed-tools`. Anything else is a Claude Code
extension and will fail validation on claude.ai uploads and the Skills API. A
skill's own version goes under `metadata:`, not a top-level `version:` key.

Version the collection with git tags. Pin tool versions in `metadata:` and state
them in the body ("Verified against KiCad 9.0"), where the agent will read them.

## License

MIT
