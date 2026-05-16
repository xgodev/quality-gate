"""Tests for the regressed fixture."""

from lib import add, multiply


# REGRESSION test: assertion errada de proposito.
def test_add_failing_on_purpose():
    assert add(2, 3) == 999


def test_multiply_positive():
    assert multiply(3, 4) == 12
