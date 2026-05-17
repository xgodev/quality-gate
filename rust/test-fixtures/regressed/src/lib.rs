// REGRESSION: fmt - line without a space after the operator (rustfmt will complain)
pub fn add(a:i32,b:i32)->i32{
    a+b
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a * b
}

// REGRESSION: lint - unused variable (clippy warning -> error with -D warnings)
pub fn unused_warning() -> i32 {
    let unused = 42;
    100
}

// REGRESSION: build - wrong type, does not compile
// pub fn type_mismatch() -> String {
//     42
// }
// (Commented out to keep it isolated in a specific test -- see Task 19/20.)

// REGRESSION: complexity - function with cognitive complexity > 25
pub fn complex_function(x: i32, y: i32) -> i32 {
    let mut r = 0;
    if x > 0 {
        if x > 10 {
            if x > 100 {
                if x > 1000 {
                    if x > 10000 {
                        if y > 0 {
                            r += 1;
                        } else {
                            r += 2;
                        }
                    } else if y > 0 {
                        r += 3;
                    } else {
                        r += 4;
                    }
                } else if x > 500 {
                    if y > 0 {
                        r += 5;
                    } else {
                        r += 6;
                    }
                } else {
                    r += 7;
                }
            } else if x > 50 {
                if x > 75 {
                    if y > 0 {
                        r += 8;
                    } else {
                        r += 9;
                    }
                } else if y > 0 {
                    r += 10;
                } else {
                    r += 11;
                }
            } else {
                r += 12;
            }
        } else if x > 5 {
            if x > 7 {
                if y > 0 {
                    r += 13;
                } else {
                    r += 14;
                }
            } else if y > 0 {
                r += 15;
            } else {
                r += 16;
            }
        } else if x > 2 {
            if y > 0 {
                r += 17;
            } else {
                r += 18;
            }
        } else {
            r += 19;
        }
    } else if x < 0 {
        if x < -10 {
            if x < -100 {
                if x < -1000 {
                    if y < 0 {
                        r += 20;
                    } else {
                        r += 21;
                    }
                } else if y < 0 {
                    r += 22;
                } else {
                    r += 23;
                }
            } else if x < -50 {
                if y < 0 {
                    r += 24;
                } else {
                    r += 25;
                }
            } else {
                r += 26;
            }
        } else if x < -5 {
            if x < -7 {
                if y < 0 {
                    r += 27;
                } else {
                    r += 28;
                }
            } else if y < 0 {
                r += 29;
            } else {
                r += 30;
            }
        } else {
            r += 31;
        }
    } else {
        r += 32;
    }
    r
}

// REGRESSION: coverage - public function without a test
pub fn uncovered() -> i32 {
    99
}

#[cfg(test)]
mod tests {
    use super::*;

    // REGRESSION: test - failing test
    #[test]
    fn test_failing_on_purpose() {
        assert_eq!(add(2, 3), 999); // wrong value on purpose
    }

    #[test]
    fn test_multiply_positive() {
        assert_eq!(multiply(3, 4), 12);
    }
}
