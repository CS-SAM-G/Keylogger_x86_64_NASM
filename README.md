# Keycrypt: Keylogger + Encrypted Socket Client (x86-64 NASM, Linux evdev)

Keycrypt is a low-level Linux keylogger and encrypted socket client written entirely in **x86-64 assembly**. It captures keyboard input through the Linux evdev subsystem, stores keystrokes in a shared-memory circular buffer, encrypts outgoing traffic with **AES-128**, and sends the data to a small C-based receiver/server for decryption and display.

The project targets **Linux x86-64 systems** and relies on the Linux evdev input interface.

The client implementation uses direct Linux syscalls instead of libc wrappers.

---

## Features

* Pure x86-64 NASM implementation
* Linux evdev keyboard capture
* Shared-memory circular buffer IPC
* Multi-process architecture
* Direct syscall-based networking
* AES-128 packet encryption
* Automatic reconnect logic
* Custom binary protocol
* Encrypted heartbeat packets
* Minimal C receiver/server

---

## Disclaimer

This project is for **educational and research purposes only**. It exists to explore low-level Linux input handling, inter-process communication, networking, and symmetric encryption in assembly.

* Do not run this on systems you do not own or do not have **explicit permission** to test.
* Unauthorized use may violate laws, organizational policies, and privacy expectations.
* The project does not attempt privilege escalation or exploitation, but its capabilities are sensitive and should be handled responsibly.

---

## High-Level Architecture

The system consists of several assembly modules plus a small C server.

### `main.asm`

Responsible for initialization and process management.

* Creates and initializes shared memory
* Spawns:

  * A keylogger process
  * A socket client process
* Monitors child processes and handles shutdown behaviour

### `common.inc`

Shared include file used across the project.

Contains:

* Constants
* Macros
* Shared structure layouts
* Circular buffer definitions
* Shared-memory variable declarations

### `keylogger.asm`

Handles keyboard capture through Linux evdev.

* Opens `/dev/input/eventX`
* Reads `struct input_event` records directly from the kernel
* Tracks modifier state:

  * Shift
  * Caps Lock
  * Key press/release state
* Converts scancodes into ASCII using custom keymaps
* Writes captured characters into the shared circular buffer

### `socket.asm`

Implements the encrypted TCP client entirely in assembly.

Responsibilities include:

* Creating TCP sockets
* Connecting and reconnecting to the server
* Reading keystrokes from shared memory
* Building protocol packets
* Converting fields to network byte order
* Encrypting packets with AES-128
* Sending heartbeat packets
* Fragmenting large payloads across multiple packets

### `encryption.asm`

Implements AES-128 entirely in assembly.

Includes:

* AES key expansion
* Round-key generation
* Block encryption routines
* Standard AES transformations:

  * SubBytes
  * ShiftRows
  * MixColumns
  * AddRoundKey

### `server.c`

A minimal C-based receiver/server.

* Accepts incoming TCP connections
* Receives encrypted packets
* Decrypts packets using the same AES key
* Parses the protocol structure
* Prints recovered keystrokes to standard output

---

## Shared Circular Buffer

The keylogger and socket client communicate through a shared-memory circular buffer created in `main.asm`.

* The keylogger appends bytes and advances the write index
* The socket client consumes bytes and advances the read index
* Both sides handle wrap-around at the end of the buffer

This design decouples keyboard capture from network transmission so temporary network delays do not block input collection.

---

## Keylogger Behavior

The keylogger captures keyboard events through the Linux evdev interface.

Behavior includes:

* Reading raw `input_event` structures
* Filtering for `EV_KEY` events
* Distinguishing between:
  * Press
  * Release
  * Hold/repeat
* Tracking modifier keys and lock state
* Translating scancodes into ASCII
* Writing valid characters into shared memory one byte at a time

---

## Socket Client and Protocol

The socket client continuously reads bytes from the shared buffer, builds packets, encrypts them, and sends them over TCP.

### Connection Handling

* Creates a TCP socket
* Connects to a configured server IP and port
* Automatically reconnects if the connection drops

### Protocol Structure

Each packet contains:

* A packet type field
* A payload length field
* Payload data

Applicable fields are converted to network byte order before transmission.

### Encryption

Packets are encrypted using **AES-128** before transmission.

* The entire packet is encrypted, including protocol headers
* Encryption operates on 16-byte blocks
* Packets are padded to a 16-byte boundary before encryption
* Encryption currently uses AES-128 in ECB mode

Encrypting the full packet reduces visible protocol structure in transmitted traffic.

### Fragmentation

If buffered data exceeds the maximum packet payload size, the client splits it across multiple encrypted packets.

### Heartbeats

The client periodically sends encrypted heartbeat packets so the server can detect dead or idle connections.

---

## AES-128 Details

`encryption.asm` implements AES-128 directly in assembly without external crypto libraries.

Key details:

* Uses a 128-bit (16-byte) symmetric key
* Performs AES key expansion internally
* Encrypts data in 16-byte blocks
* Uses 10 AES rounds per block

Each round applies the standard AES transformations:

* SubBytes
* ShiftRows
* MixColumns (except during the final round)
* AddRoundKey

The C server uses a compatible AES implementation and the same key to decrypt incoming packets.

---

## Example Program Flow

```text
main.asm:
  init shared memory
  fork keylogger process
  fork socket process
  monitor socket process

keylogger.asm:
  open /dev/input/eventX
  loop:
    read input_event
    update flags (shift, caps, pressed)
    convert scancode to ASCII
    write character into circular buffer

socket.asm:
  loop:
    ensure TCP connection (connect / reconnect)
    read bytes from circular buffer
    assemble protocol packet (type, length, payload)
    encrypt entire packet with AES-128
    send encrypted packet
    send periodic encrypted heartbeat packets
```

---

## Requirements

Install the required build tools:

* NASM
* GNU binutils (`ld`)
* GCC
* Bash

On Debian/Ubuntu-based systems:

```bash
sudo apt install nasm binutils gcc
```

---

## Build

Run the build script:

```bash
chmod +x build.sh
./build.sh
```

The compiled client binary will be placed in:

```text
build/keycrypt
```

Compile the server separately:

```bash
gcc server.c -o server
```

---

## Manual Build

If you prefer to build manually:

```bash
mkdir -p build

nasm -f elf64 -g -F dwarf -I src src/main.asm -o build/main.o
nasm -f elf64 -g -F dwarf -I src src/keylogger.asm -o build/keylogger.o
nasm -f elf64 -g -F dwarf -I src src/socket.asm -o build/socket.o
nasm -f elf64 -g -F dwarf -I src src/encryption.asm -o build/encryption.o

ld -o build/keycrypt \
    build/main.o \
    build/keylogger.o \
    build/socket.o \
    build/encryption.o \
    -e _start
```

---

## Usage

Because the program reads from `/dev/input/eventX`, it typically requires **root privileges**.

### 1. Identify your keyboard device

```bash
cat /proc/bus/input/devices
```

Find the correct `/dev/input/eventX` device for your keyboard.

### 2. Configure the client

Update:

* The evdev device path in `keylogger.asm`
* The server IP address in `socket.asm`
* The port number in both:

  * `socket.asm`
  * `server.c`

### 3. Build the project

Build:

* The NASM client
* The C server

### 4. Start the server

```bash
./server
```

### 5. Run the client

```bash
sudo ./build/keycrypt
```

If everything is configured correctly, decrypted keystrokes will appear in the server terminal as keyboard input is captured.
