SIDESTORE_REPO ?= ../../../SideStore
# SIDESTORE_REPO ?= ../SideStore
SKIP_SIM ?= false
TARGET=minimuxer

add_targets:
	@echo "add_targets"
	rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

compile:
	@echo "build aarch64-apple-ios"
	@# @cargo build --release --target aarch64-apple-ios
	@cargo build --target aarch64-apple-ios
	@# @cp target/aarch64-apple-ios/release/lib$(TARGET).a target/lib$(TARGET)-ios.a
	@cp target/aarch64-apple-ios/debug/lib$(TARGET).a target/lib$(TARGET)-ios.a

ifeq ($(SKIP_SIM),false)
	@echo "build aarch64-apple-ios-sim"
	@# @cargo build --release --target aarch64-apple-ios-sim
	@cargo build --target aarch64-apple-ios-sim

	@echo "build x86_64-apple-ios"
	@# @cargo build --release --target x86_64-apple-ios
	@cargo build --target x86_64-apple-ios

	@echo "lipo"
	@# @lipo -create \
	@# 	-output target/lib$(TARGET)-sim.a \
	@# 	target/aarch64-apple-ios-sim/release/lib$(TARGET).a \
	@# 	target/x86_64-apple-ios/release/lib$(TARGET).a
	@lipo -create \
		-output target/lib$(TARGET)-sim.a \
		target/aarch64-apple-ios-sim/debug/lib$(TARGET).a \
		target/x86_64-apple-ios/debug/lib$(TARGET).a
else
	@echo "skipping sim builds"
endif

# TODO: remove/update once SPM gets merged
copy:
	@echo "SIDESTORE_REPO: $(SIDESTORE_REPO)"

	@echo "copying libraries"
	@cp target/lib$(TARGET)-ios.a "$(SIDESTORE_REPO)/SideStore/minimuxer"
	@cp target/lib$(TARGET)-sim.a "$(SIDESTORE_REPO)/SideStore/minimuxer"

	@echo "copying generated"
	@cp generated/* "$(SIDESTORE_REPO)/SideStore/minimuxer"

	@touch "$(SIDESTORE_REPO)/SideStore/.skip-prebuilt-fetch-minimuxer"

# build: compile copy
build: compile

clean:
	@echo "clean"
	@if [ -d "include" ]; then \
		echo "cleaning include"; \
		rm -r include; \
	fi
	@if [ -d "target" ]; then \
		echo "cleaning target"; \
		rm -r target; \
	fi
	@if [ -d "$(TARGET).xcframework" ]; then \
		echo "cleaning $(TARGET).xcframework"; \
		rm -r $(TARGET).xcframework; \
	fi
	@if [ -f "$(TARGET).xcframework.zip" ]; then \
		echo "cleaning $(TARGET).xcframework.zip"; \
		rm $(TARGET).xcframework.zip; \
	fi
	@rm -f *.h *.swift
	@rm -f *.a

xcframework: build
	@echo "xcframework"

	@if [ -d "include" ]; then \
		echo "cleaning include"; \
		rm -rf include; \
	fi
	@mkdir include
	@mkdir include/$(TARGET)/
	@cp generated/*.h include/$(TARGET)/
	@cp module.modulemap include/$(TARGET)/

	@if [ -d "$(TARGET).xcframework" ]; then \
		echo "cleaning $(TARGET).xcframework"; \
		rm -rf $(TARGET).xcframework; \
	fi

	@xcodebuild \
		-create-xcframework \
		-library target/lib$(TARGET)-ios.a \
		-headers include/ \
		-library target/lib$(TARGET)-sim.a \
		-headers include/ \
		-output $(TARGET).xcframework


xcframework_frameworks: build
	@echo "xcframework_frameworks"

	@if [ -d "include" ]; then \
		echo "cleaning include"; \
		rm -rf include; \
	fi
	@mkdir include
	@mkdir include/$(TARGET)
	@cp generated/*.h include/$(TARGET)
	@cp module.modulemap include/$(TARGET)

	@if [ -d "target/ios" ]; then \
		echo "cleaning target/ios"; \
		rm -rf target/ios; \
	fi
	@mkdir -p target/ios/$(TARGET).framework/Headers
	@mkdir -p target/ios/$(TARGET).framework/Modules
	cp include/$(TARGET)/*.h target/ios/$(TARGET).framework/Headers
	cp include/$(TARGET)/module.modulemap target/ios/$(TARGET).framework/Modules/

	@if [ -d "target/sim" ]; then \
		echo "cleaning target/sim"; \
		rm -rf target/sim; \
	fi
	@mkdir -p target/sim/$(TARGET).framework/Headers
	@mkdir -p target/sim/$(TARGET).framework/Modules
	cp include/$(TARGET)/*.h target/sim/$(TARGET).framework/Headers
	cp include/$(TARGET)/module.modulemap target/sim/$(TARGET).framework/Modules/

	@libtool -static \
		-o target/ios/$(TARGET).framework/$(TARGET) \
		target/lib$(TARGET)-ios.a

	@xcrun \
		-sdk iphonesimulator \
		libtool -static \
		-o target/sim/$(TARGET).framework/$(TARGET) \
		target/lib$(TARGET)-sim.a

	@plutil -create xml1 target/ios/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleName -string $(TARGET) target/ios/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleIdentifier -string org.sidestore.$(TARGET) target/ios/$(TARGET).framework/Info.plist
	@plutil -replace CFBundlePackageType -string FMWK target/ios/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleVersion -string 1 target/ios/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleShortVersionString -string 1.0 target/ios/$(TARGET).framework/Info.plist

	@plutil -create xml1 target/sim/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleName -string $(TARGET) target/sim/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleIdentifier -string org.sidestore.$(TARGET) target/sim/$(TARGET).framework/Info.plist
	@plutil -replace CFBundlePackageType -string FMWK target/sim/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleVersion -string 1 target/sim/$(TARGET).framework/Info.plist
	@plutil -replace CFBundleShortVersionString -string 1.0 target/sim/$(TARGET).framework/Info.plist

	@if [ -d "$(TARGET).xcframework" ]; then \
		echo "cleaning $(TARGET).xcframework"; \
		rm -rf $(TARGET).xcframework; \
	fi

	@xcodebuild -create-xcframework \
		-framework target/sim/$(TARGET).framework \
		-framework target/ios/$(TARGET).framework \
		-output $(TARGET).xcframework


zip: xcframework
	@echo "zip xcframework"
	@if [ -f "$(TARGET).xcframework.zip" ]; then \
		echo "cleaning $(TARGET).xcframework.zip"; \
		rm $(TARGET).xcframework.zip; \
	fi
	zip -r $(TARGET).xcframework.zip $(TARGET).xcframework

	@echo "zip generated"
	@zip -r generated.zip generated/
