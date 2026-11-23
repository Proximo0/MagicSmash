"""Load the MPFB body generator in a windowless Blender.

Blender 5 only lets the generator find its own folders when it is loaded as an extension (module
bl_ext.user_default.mpfb), not from sys.path, so the source folder is copied once into the user's extension folder.
Call load() after any read_factory_settings: a factory reset switches every add-on off again.
"""
import importlib
import os
import shutil

import addon_utils
import bpy

MODULE = "bl_ext.user_default.mpfb"


def load(mpfb_src):
    """mpfb_src = the checkout's src folder (holds mpfb/).  Returns (HumanService, TargetService)."""
    dest = os.path.join(bpy.utils.user_resource("EXTENSIONS", path="user_default", create=True), "mpfb")
    if not os.path.isdir(dest):
        shutil.copytree(os.path.join(mpfb_src, "mpfb"), dest)
    addon_utils.enable(MODULE, default_set=False)
    return (importlib.import_module(MODULE + ".services.humanservice").HumanService,
            importlib.import_module(MODULE + ".services.targetservice").TargetService)
