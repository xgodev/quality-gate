package qgregressed

import "fmt"

// REGRESSION fmt: indentacao com espacos (gofmt vai reclamar).
func Add(a, b int) int {
    return a + b
}

// Multiply mantem-se formatado.
func Multiply(a, b int) int {
	return a * b
}

// REGRESSION lint: erro de Printf detectado por go vet/govet (em golangci-lint).
// Format string %d sem argumento e argumento extra.
func BadPrintf() {
	_ = fmt.Sprintf("%d", "string-em-vez-de-int")
}

// REGRESSION coverage: funcao publica sem teste correspondente.
func Uncovered() int {
	return 99
}

// REGRESSION complexity: funcao com complexidade ciclomatica > 15.
func ComplexFunction(x, y int) int {
	r := 0
	if x > 0 {
		if x > 10 {
			if x > 100 {
				if x > 1000 {
					if y > 0 {
						r += 1
					} else {
						r += 2
					}
				} else if y > 0 {
					r += 3
				} else {
					r += 4
				}
			} else if x > 50 {
				if y > 0 {
					r += 5
				} else {
					r += 6
				}
			} else {
				r += 7
			}
		} else if x > 5 {
			if y > 0 {
				r += 8
			} else {
				r += 9
			}
		} else if x > 2 {
			if y > 0 {
				r += 10
			} else {
				r += 11
			}
		} else {
			r += 12
		}
	} else if x < 0 {
		if x < -10 {
			if y < 0 {
				r += 13
			} else {
				r += 14
			}
		} else if y < 0 {
			r += 15
		} else {
			r += 16
		}
	} else {
		r += 17
	}
	return r
}
