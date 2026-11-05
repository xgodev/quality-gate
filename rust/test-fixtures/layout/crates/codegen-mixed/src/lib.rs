//! Generated protos AND the adapters that map them: every edit to the adapter
//! recompiles the generated code too.
tonic::include_proto!("api");

mod adapter;

pub use adapter::to_domain;
