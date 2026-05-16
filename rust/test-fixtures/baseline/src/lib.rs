pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub fn multiply(a: i32, b: i32) -> i32 {
    a * b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_positive() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    fn test_add_negative() {
        assert_eq!(add(-1, -1), -2);
    }

    #[test]
    fn test_multiply_positive() {
        assert_eq!(multiply(3, 4), 12);
    }

    #[test]
    fn test_multiply_zero() {
        assert_eq!(multiply(0, 5), 0);
    }
}
