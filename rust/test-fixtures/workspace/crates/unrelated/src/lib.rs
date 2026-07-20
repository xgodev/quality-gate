pub fn unrelated_value() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(super::unrelated_value(), 42);
    }
}
