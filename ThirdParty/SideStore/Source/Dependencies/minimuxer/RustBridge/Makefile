TARGET=rust_bridge
RUST_DIR="."
SCHEME=Minimuxer
BUILD_DIR=lib
FRAMEWORK_NAME=Minimuxer

.PHONY: all build rust xcframework zip clean

# --- Core Build ---

all: build

build: rust

rust:
	@echo "--- Building Rust Bridge ---"

	@# iOS device (arm64)
	cd $(RUST_DIR) && cargo build --target aarch64-apple-ios --release

	@# iOS Simulator (Apple Silicon)
	cd $(RUST_DIR) && cargo build --target aarch64-apple-ios-sim --release

	@# macOS (arm64)
	cd $(RUST_DIR) && cargo build --target aarch64-apple-darwin --release


# --- XCFramework from static libs (no C headers needed — Swift uses @_silgen_name) ---

xcframework: rust
	@echo "--- Building RustBridge.xcframework ---"

	@# Empty headers dir required by xcodebuild -create-xcframework -library
	mkdir -p $(RUST_DIR)/lib/headers

	@# Remove stale xcframework
	rm -rf $(RUST_DIR)/lib/RustBridge.xcframework

	xcodebuild -create-xcframework \
		-library $(RUST_DIR)/target/aarch64-apple-ios/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-library $(RUST_DIR)/target/aarch64-apple-ios-sim/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-library $(RUST_DIR)/target/aarch64-apple-darwin/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-output $(RUST_DIR)/lib/RustBridge.xcframework

	@echo "--- Done: RustBridge/lib/RustBridge.xcframework ---"


# --- Cleanup ---

clean:
	@echo "--- Cleaning ---"
	cd $(RUST_DIR) && cargo clean
	rm -rf $(RUST_DIR)/lib
