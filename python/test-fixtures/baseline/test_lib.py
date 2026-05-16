"""Tests for the baseline fixture."""

from lib import add, multiply


def test_add_positive():
    assert add(2, 3) == 5


def test_add_negative():
    assert add(-1, -1) == -2


def test_multiply_positive():
    assert multiply(3, 4) == 12


def test_multiply_zero():
    assert multiply(0, 5) == 0
