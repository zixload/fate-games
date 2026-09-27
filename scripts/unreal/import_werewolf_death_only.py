"""Reimport only the revised Werewolf death and reclined idle FBX files."""

from pathlib import Path

script = Path("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/"
              "import_werewolf_vote_point_and_death.py")
scope = {"WW_DEATH_ONLY": True}
exec(compile(script.read_text(encoding="utf-8"), str(script), "exec"), scope)
