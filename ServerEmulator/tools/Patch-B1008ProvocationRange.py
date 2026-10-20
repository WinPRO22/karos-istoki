"""Approved rank-dependent taunt radius; compose with existing local skill fixes."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'profession_levels', Path(__file__).with_name('Patch-B1008ProfessionLevels.py'))
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

if __name__ == '__main__':
    patch.main('provocation')
