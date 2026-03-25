#!/bin/bash
# build.sh
# Author: Samuel Gould
# Date: 2026-03-24

set -e

# Output
OBJ_DIR=build
BIN=keycrypt
NASM_FLAGS="-f elf64 -g -F dwarf -I src"

# Sources
SOURCES=("src/main.asm" "src/keylogger.asm" "src/socket.asm" "src/encryption.asm")
OBJECTS=()

# Create build directory
mkdir -p "$OBJ_DIR"

# Assemble each source file
echo "Assembling sources..."
for src in "${SOURCES[@]}"; do
    obj="$OBJ_DIR/$(basename ${src%.*}.o)"
    OBJECTS+=("$obj")
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
        echo "  [NASM] $src -> $obj"
        nasm $NASM_FLAGS "$src" -o "$obj"
    else
        echo "  [SKIP] $src (up to date)"
    fi
done

echo "Linking binary..."
ld -o "$OBJ_DIR/$BIN" "${OBJECTS[@]}" -e _start

echo "Build complete. Binary created at $OBJ_DIR/$BIN"
