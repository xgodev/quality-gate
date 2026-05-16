package qgbaseline

import "testing"

func TestAddPositive(t *testing.T) {
	if Add(2, 3) != 5 {
		t.Fatalf("expected 5")
	}
}

func TestAddNegative(t *testing.T) {
	if Add(-1, -1) != -2 {
		t.Fatalf("expected -2")
	}
}

func TestMultiplyPositive(t *testing.T) {
	if Multiply(3, 4) != 12 {
		t.Fatalf("expected 12")
	}
}

func TestMultiplyZero(t *testing.T) {
	if Multiply(0, 5) != 0 {
		t.Fatalf("expected 0")
	}
}
