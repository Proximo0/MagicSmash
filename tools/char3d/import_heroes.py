#!/usr/bin/env python3
"""Kept for old habits: import_heroes.py <heroes24 dir> <art dir> is import_sprites.py heroes <dir> <art dir>."""
import sys

from import_sprites import main

if __name__ == "__main__":
    main([sys.argv[0], "heroes"] + sys.argv[1:])
