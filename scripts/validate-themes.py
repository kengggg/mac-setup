#!/usr/bin/env python3
"""Validate complete matching Lanna Tone palettes before publishing either copy."""
import re
import sys
import tomllib
from pathlib import Path


def validate(ghostty, alacritty):
    colors = {}
    palette = {}
    for line in Path(ghostty).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, value = (part.strip() for part in line.split('=', 1))
        if key == 'palette':
            index, value = (part.strip() for part in value.split('=', 1))
            index = int(index)
            if index in palette or not 0 <= index < 16:
                raise ValueError('duplicate or out-of-range palette entry')
            palette[index] = value.lstrip('#').lower()
        else:
            if key in colors:
                raise ValueError(f'duplicate Ghostty key: {key}')
            colors[key] = value.lstrip('#').lower()
    required = {'background', 'foreground', 'cursor-color', 'cursor-text',
                'selection-background', 'selection-foreground'}
    if not required <= colors.keys() or set(palette) != set(range(16)):
        raise ValueError('incomplete Ghostty colors or palette')
    for value in [*(colors[key] for key in required), *palette.values()]:
        if not re.fullmatch('[0-9a-f]{6}', value):
            raise ValueError(f'invalid RGB color: {value}')
    data = tomllib.loads(Path(alacritty).read_text())['colors']
    def color(section, key):
        value = data[section][key]
        if not re.fullmatch('#[0-9a-fA-F]{6}', value):
            raise ValueError(f'invalid Alacritty color: {section}.{key}')
        return value[1:].lower()
    for key in ('background', 'foreground'):
        if color('primary', key) != colors[key]:
            raise ValueError(f'theme {key} colors differ')
    for offset, section in ((0, 'normal'), (8, 'bright')):
        for index, key in enumerate(('black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white')):
            if color(section, key) != palette[index + offset]:
                raise ValueError(f'theme palette colors differ: {section}.{key}')


if __name__ == '__main__':
    try:
        validate(*sys.argv[1:])
    except (ValueError, KeyError, TypeError, OSError) as error:
        sys.exit(f'invalid theme download: {error}')
