use std::env;
use std::path::PathBuf;

fn main() {
    // Search order: TURBOTOKEN_NATIVE_LIB env, zig-out/lib/, system paths
    let lib_dir = if let Ok(dir) = env::var("TURBOTOKEN_NATIVE_LIB") {
        PathBuf::from(dir)
    } else {
        let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
        let zig_out = manifest.parent().unwrap().join("zig-out").join("lib");
        if zig_out.exists() {
            zig_out
        } else {
            // Fall back to /usr/local/lib
            PathBuf::from("/usr/local/lib")
        }
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=turbotoken");

    #[cfg(feature = "bindgen")]
    {
        let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
        let header = manifest
            .parent()
            .unwrap()
            .join("include")
            .join("turbotoken.h");

        let bindings = bindgen::Builder::default()
            .header(header.to_string_lossy())
            .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
            .generate()
            .expect("Unable to generate bindings");

        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings
            .write_to_file(out_path.join("bindings.rs"))
            .expect("Couldn't write bindings");
    }
}
