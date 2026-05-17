"""Regressed module for the Python quality gate fixture."""

import os  # REGRESSION lint: import unused (ruff F401)


# REGRESSION fmt: indentacao inconsistente (ruff format vai reclamar)
def add(a:int,b:int)->int:
    """Return the sum of two integers."""
    return a+b


def multiply(a: int, b: int) -> int:
    """Return the product of two integers."""
    return a * b


# REGRESSION coverage: public function without a corresponding test.
def uncovered() -> int:
    return 99


# REGRESSION complexity: function with cyclomatic complexity > radon C threshold (>10).
def complex_function(x: int, y: int) -> int:
    r = 0
    if x > 0:
        if x > 10:
            if x > 100:
                if x > 1000:
                    if y > 0:
                        r += 1
                    else:
                        r += 2
                elif y > 0:
                    r += 3
                else:
                    r += 4
            elif x > 50:
                if y > 0:
                    r += 5
                else:
                    r += 6
            else:
                r += 7
        elif x > 5:
            if y > 0:
                r += 8
            else:
                r += 9
        elif x > 2:
            if y > 0:
                r += 10
            else:
                r += 11
        else:
            r += 12
    elif x < 0:
        if x < -10:
            if y < 0:
                r += 13
            else:
                r += 14
        elif y < 0:
            r += 15
        else:
            r += 16
    else:
        r += 17
    return r
