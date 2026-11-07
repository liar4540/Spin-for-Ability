# Spin for Abilities

A Roblox game: spin for free to roll anime-style abilities (9 rarities, Common to Secret), upgrade them with Shards, and fight in a battlegrounds arena.

| Folder | What's in it | Open it with |
|---|---|---|
| [`Spin for Abilities Vault/`](Spin%20for%20Abilities%20Vault/) | The game plan: concept, systems, monetization, UI, tech plan, roadmap, abilities (start at `Game Plan Vault/00 Home.md`) | [Obsidian](https://obsidian.md) (Open folder as vault), or just read the `.md` files on GitHub |
| [`Game/`](Game/) | The code (Rojo + Luau) and the Blender VFX kit (`Game/assets/vfx`) | VS Code + Roblox Studio. Setup steps in [`Game/README.md`](Game/README.md) |

## Getting started (for collaborators)

1. Clone this repo (GitHub Desktop: *File → Clone repository*, or `git clone https://github.com/liar4540/Spin-for-Ability.git`).
2. **Plan:** open `Spin for Abilities Vault` in Obsidian.
3. **Code:** follow [`Game/README.md`](Game/README.md): install Aftman → `aftman install` in `Game/` → `rojo build` → open in Studio → `rojo serve` + Connect.
4. **Maps, UI and VFX built in Studio** aren't in this repo (Rojo only syncs `src/`). They live in the published Roblox place: ask the owner to add you in Studio under **Collaboration** (Team Create).
5. **VFX meshes:** rebuilt from `Game/assets/vfx/_src/build_vfx.py` with Blender 5.2 (`blender -b --factory-startup --python build_vfx.py`).

Never commit Obsidian plugin settings or any API keys; the `.gitignore` files already block the usual ones.

/add-dir C:/Roblox/Anime-Stand/src/LIH.FOLK.VAULT.V2.FULL
"Continue Thunder Lance from Stage 7. Stage 6 is ok."