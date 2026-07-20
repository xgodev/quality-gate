pub fn leaf_value() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(super::leaf_value(), 42);
    }
}
