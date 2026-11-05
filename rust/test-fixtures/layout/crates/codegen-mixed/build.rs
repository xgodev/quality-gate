fn main() {
    prost_build::compile_protos(&["proto/api.proto"], &["proto"]).unwrap();
}
