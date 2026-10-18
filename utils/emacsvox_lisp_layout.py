"""Read the shared Lisp directory registry for source-only payloads."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

from pathlib import Path
import re
import stat


def directory_names(contents):
    """Parse registry text, including when checking a source archive."""
    names = []
    for line in contents.splitlines():
        name = line.strip()
        if not name or name.startswith('#'):
            continue
        if (name != '.' and not re.fullmatch(r'[a-z][a-z0-9-]*', name)) or name in names:
            raise ValueError(f'Invalid or duplicate Lisp directory: {name}')
        names.append(name)
    if not names or names[0] != '.':
        raise ValueError('Lisp directory registry must start with the bootstrap root')
    return names


def directories(root):
    """Validate declared parents without following child directory links."""
    names = directory_names((root / 'etc/lisp-directories').read_text())
    for name in names:
        path = root / 'lisp' / name
        try:
            attributes = path.lstat()
        except FileNotFoundError:
            if name == '.':
                raise ValueError(f'Missing Lisp root: {path}') from None
            continue
        if ((name != '.' and (stat.S_ISLNK(attributes.st_mode) or
                getattr(attributes, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT))
                or not path.is_dir()):
            raise ValueError(f'Invalid Lisp directory: {path}')
    return names


def includes(name, parents):
    """Select a visible source directly inside a declared Lisp directory."""
    path = Path(name)
    return (path.suffix == '.el' and not any(p.startswith('.') for p in path.parts)
            and path.parent in {Path('lisp') / parent for parent in parents})


def sources(root):
    """Return relative source paths, rejecting links and library collisions."""
    seen = {}
    result = []
    for parent in directories(root):
        for path in sorted((root / 'lisp' / parent).glob('*.el')):
            if path.name.startswith('.'):
                continue
            if path.is_symlink() or not path.is_file():
                raise ValueError(f'Missing regular payload file: {path}')
            if not re.fullmatch(r'[a-zA-Z0-9_-]+\.el', path.name):
                raise ValueError(f'Invalid Lisp source name: {path}')
            key = path.name.casefold()
            if key in seen:
                raise ValueError(f'Duplicate Lisp library: {seen[key]} and {path}')
            seen[key] = path
            result.append(path.relative_to(root).as_posix())
    return result


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    arguments = parser.parse_args()
    for name in sources(arguments.root):
        print(name)
