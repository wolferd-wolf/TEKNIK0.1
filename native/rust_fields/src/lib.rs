// godot 0.1.3 generated call shims return a large CallError by value.
// The size is fixed by the upstream crate, not by extension code.
#![allow(clippy::result_large_err)]

use godot::prelude::*;

// Step 7 bootstrap class: proves the Rust GDExtension loads into Godot 4.3
// and is callable from gates. Real field modules arrive with step 8.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct TeknikRustProbe {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for TeknikRustProbe {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl TeknikRustProbe {
    #[func]
    pub fn ping(&self) -> i64 {
        42
    }
}

struct TeknikRustFieldsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for TeknikRustFieldsExtension {}
