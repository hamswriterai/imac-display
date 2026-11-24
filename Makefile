SWIFTC     := swiftc -O -swift-version 5
# The Command Line Tools lack x86_64 Swift compatibility libs; this code does not need them.
COMPAT     := -runtime-compatibility-version none
ARCHS      := x86_64 arm64

SENDER_SRC   := Shared/Common.swift Sender/main.swift
RECEIVER_SRC := Shared/Common.swift Receiver/main.swift

all: build/sender build/receiver

# Sender: needs macOS 12.3+ (ScreenCaptureKit). Universal.
build/sender-%: $(SENDER_SRC) Sender/Bridging.h
	@mkdir -p build
	$(SWIFTC) $(COMPAT) -target $*-apple-macos12.3 -import-objc-header Sender/Bridging.h $(SENDER_SRC) -o $@

# Receiver: macOS 12.0+. Universal (Intel iMac + Apple Silicon Macs).
build/receiver-%: $(RECEIVER_SRC)
	@mkdir -p build
	$(SWIFTC) $(COMPAT) -target $*-apple-macos12.0 $(RECEIVER_SRC) -o $@

build/sender: $(addprefix build/sender-,$(ARCHS))
	lipo -create $^ -o $@
	codesign -s - -f $@

build/receiver: $(addprefix build/receiver-,$(ARCHS))
	lipo -create $^ -o $@
	codesign -s - -f $@

# .app bundles + disk image
dmg: all
	./Packaging/package.sh

clean:
	rm -rf build

.PHONY: all dmg clean
