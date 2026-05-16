package qgregressed

import "testing"

// REGRESSION test: teste falhando de proposito.
func TestAddFailingOnPurpose(t *testing.T) {
	if Add(2, 3) != 999 {
		t.Fatalf("expected 999 (de proposito errado)")
	}
}

func TestMultiplyPositive(t *testing.T) {
	if Multiply(3, 4) != 12 {
		t.Fatalf("expected 12")
	}
}
