pub fn mid_value() -> u32 {
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(super::mid_value(), 42);
    }
}
