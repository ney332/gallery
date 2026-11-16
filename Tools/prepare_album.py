"""Detach rigid page meshes from the cover skeleton for independent RealityKit turns.
Usage: python3 Tools/prepare_album.py /path/to/album.usdz /path/to/Models/album.usdz
The source is never modified. Requires Apple's usdcat (included with Xcode tools).
"""
import pathlib
import subprocess
import sys
import tempfile

source, destination = map(pathlib.Path, sys.argv[1:])
if source.resolve() == destination.resolve():
    raise SystemExit('Source and destination must differ')
with tempfile.TemporaryDirectory(prefix='gallery-album-') as directory:
    text_file = pathlib.Path(directory) / 'album.usda'
    subprocess.run(['usdcat', str(source), '-o', str(text_file)], check=True)
    text = text_file.read_text()
    for name in ('PaginaBaixo', 'PaginaMeio', 'PaginaTopo'):
        start = text.index(f'    def Xform "{name}"')
        opening = text.index('{', start)
        depth = 1
        end = opening + 1
        while depth:
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        block = text[start:end]
        block = block.replace('"MaterialBindingAPI", "SkelBindingAPI"', '"MaterialBindingAPI"')
        lines = []
        skipping_metadata = False
        for line in block.splitlines():
            if skipping_metadata:
                if line.strip() == ')':
                    skipping_metadata = False
                continue
            if 'primvars:skel:' in line or 'rel skel:' in line:
                skipping_metadata = line.rstrip().endswith('(')
                continue
            lines.append(line)
        block = '\n'.join(lines)
        if 'skel:' in block or 'SkelBindingAPI' in block:
            raise RuntimeError(f'Unprocessed binding: {name}')
        text = text[:start] + block + text[end:]
    # The room controls lighting; the exported dome points to a Blender EXR.
    start = text.find('    def DomeLight "env_light"')
    if start >= 0:
        opening = text.index('{', start)
        end, depth = opening + 1, 1
        while depth:
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        text = text[:start] + text[end:]
    text_file.write_text(text)
    destination.parent.mkdir(parents=True, exist_ok=True)
    binary = pathlib.Path(directory) / 'album.usdc'
    subprocess.run(['usdcat', str(text_file), '-o', str(binary)], check=True)
    subprocess.run(['usdzip', str(destination.resolve()), '-a', str(binary)], check=True)
