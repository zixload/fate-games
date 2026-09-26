"""Insert DefaultSlot before the Creative AnimGraph root and save the asset.

Requires the editor-only CodexAnimGraphEditor plugin shipped alongside this
script. It is idempotent and leaves the existing seated pose graph connected.
"""

import unreal


PATH = '/Game/MyAssetPack/Creative_Characters_FREE/Animations/ABP_Creative'
blueprint = unreal.EditorAssetLibrary.load_asset(PATH)
if not blueprint:
    raise RuntimeError(f'Missing Animation Blueprint: {PATH}')

if not unreal.CodexAnimGraphLibrary.ensure_default_slot(blueprint):
    raise RuntimeError('Cannot connect DefaultSlot to the AnimGraph output')
if not unreal.CodexAnimGraphLibrary.ensure_seated_look(blueprint):
    raise RuntimeError('Cannot connect the seated head look controls')

unreal.BlueprintEditorLibrary.compile_blueprint(blueprint)
if not unreal.EditorAssetLibrary.save_loaded_asset(blueprint):
    raise RuntimeError('Cannot save Creative Animation Blueprint')

unreal.log('CodexAnimation DefaultSlot ready in ABP_Creative')
