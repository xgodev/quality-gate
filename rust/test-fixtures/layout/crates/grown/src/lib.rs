pub fn f1() -> u32 {
    1
}

pub fn f2() -> u32 {
    2
}

pub fn f3() -> u32 {
    3
}

pub fn f4() -> u32 {
    4
}

pub fn f5() -> u32 {
    5
}

pub fn f6() -> u32 {
    6
}

pub fn f7() -> u32 {
    7
}

pub fn f8() -> u32 {
    8
}

pub fn f9() -> u32 {
    9
}

pub fn f10() -> u32 {
    10
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_adds_up() {
        assert_eq!(f1() + f2(), 3);
    }
}
