"""Apply the local Wind Barrier +4 tooltip, preserving profession level fixes."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'profession_levels', Path(__file__).with_name('Patch-B1008ProfessionLevels.py'))
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

if __name__ == '__main__':
    patch.main('tooltip')
