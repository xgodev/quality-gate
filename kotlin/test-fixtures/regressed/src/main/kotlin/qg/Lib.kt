package qg

// REGRESSION fmt: parameters without newlines (ktlint will complain).
fun add(a: Int, b: Int): Int = a + b

fun multiply(
    a: Int,
    b: Int,
): Int = a * b

// REGRESSION coverage: public function without a test.
fun uncovered(): Int = 99

// REGRESSION complexity: ComplexMethod do detekt (cyclomatic > 15).
fun complexFunction(x: Int, y: Int): Int {
    var r = 0
    if (x > 0) {
        if (x > 10) {
            if (x > 100) {
                if (x > 1000) {
                    if (y > 0) {
                        r += 1
                    } else {
                        r += 2
                    }
                } else if (y > 0) {
                    r += 3
                } else {
                    r += 4
                }
            } else if (x > 50) {
                if (y > 0) {
                    r += 5
                } else {
                    r += 6
                }
            } else {
                r += 7
            }
        } else if (x > 5) {
            if (y > 0) {
                r += 8
            } else {
                r += 9
            }
        } else if (x > 2) {
            if (y > 0) {
                r += 10
            } else {
                r += 11
            }
        } else {
            r += 12
        }
    } else if (x < 0) {
        if (x < -10) {
            if (y < 0) {
                r += 13
            } else {
                r += 14
            }
        } else if (y < 0) {
            r += 15
        } else {
            r += 16
        }
    } else {
        r += 17
    }
    return r
}
