"""Pure path-shape checks for preflight; concurrent filesystem writers unsupported."""
from pathlib import Path, PurePosixPath
import stat


def validate_layout(files, directories=()):
    """Reject file/directory aliases and files used as parents, in any order."""
    files = set(files)
    dirs = set(directories)
    for name in files | dirs:
        path = PurePosixPath(name)
        if (not name or path.is_absolute() or '\\' in name or ':' in name
                or any(part in ('', '.', '..') for part in name.split('/'))):
            raise ValueError('unsafe archive path: ' + name)
        dirs.update(str(parent) for parent in path.parents if str(parent) != '.')
    conflicts = files & dirs
    if conflicts:
        raise ValueError('file/directory path conflict: ' + sorted(conflicts)[0])


def checked_destination(path):
    """Validate existing parents and require a genuinely absent destination."""
    path = Path(path).absolute()
    if '..' in path.parts:
        raise ValueError('destination must not contain parent traversal')
    for parent in reversed([path, *path.parents]):
        try:
            mode = parent.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
            raise ValueError('destination parent must be an unlinked directory: ' + str(parent))
        if parent == path:
            raise ValueError('destination already exists: ' + str(path))
    return path
