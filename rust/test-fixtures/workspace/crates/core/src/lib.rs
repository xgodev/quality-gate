pub fn core_value() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(super::core_value(), 42);
    }
}
