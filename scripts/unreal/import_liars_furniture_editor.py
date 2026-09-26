"""Run furniture import in the full Unreal editor, then exit without cooking."""

import runpy
import unreal


try:
    runpy.run_path("C:/Users/ingam/OneDrive/Documents/fate-games/scripts/unreal/import_liars_furniture.py")
finally:
    unreal.SystemLibrary.quit_editor()
