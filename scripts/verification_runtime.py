"""Fail before running checks that rely on Python assertion statements."""


def require_assertions():
    if not __debug__:
        raise SystemExit('verification requires assertions; Python optimization is unsupported')
