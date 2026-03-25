
# Keylogger (x86-64 NASM, Linux evdev)

Low-level Linux keylogger implemented in **x86-64 NASM**, directly interfacing with input events.

---

## Disclaimer

This project is for **educational purposes only**. It does not use exploits and is not intended for malicious use.

Use this code at your own risk. It should only be run on systems you own or have explicit permission to test. Unauthorized use of this type of software may violate privacy laws and system policies.

This project was developed as a low-level learning exercise focused on **Linux syscalls**, **kernel-level input handling**, and foundational concepts behind how malware operates (specifically input capture techniques). While it is fully functional in the tested environment, it is not intended to be a production-ready or universally compatible keylogger across all Linux distributions or hardware configurations.

---

## Overview

This project is a keylogger written entirely in **x86-64 NASM assembly** that captures global keyboard input at the system level on Linux using the `/dev/input` evdev interface.

On Linux, a program can read keyboard events outside a specific application by opening a device under /dev/input/eventX and consuming the kernel’s input_event records through the evdev interface. This reads low-level input events before they reach normal application input handling, so it does not rely on terminal echo or per-application keyboard input paths.

---

## Features

- Global keyboard input capture (independent of terminal or application)  
- Direct kernel-level input reading via `/dev/input/eventX`  
- Full implementation in x86-64 assembly (NASM)
- Manual parsing of `input_event` structures  
- ASCII conversion using custom keymap tables  
- Correct handling of:
  - Key press, release, and hold events  
  - Shift  
  - Caps Lock toggle  
- Accurate letter vs symbol mapping logic  
- File logging using raw syscalls  
- Modular design using macros and procedure-like structure  

---

## Program Flow
```
Init:
Read_loop:
  Read_event
  Handle_event
  Convert_to_ascii
  Log_event
  loop
Cleanup:
```
### Init
- Set uninitialzed flags reserved in .bss
- Open/create directory and log file 

### Read_event
- Reads **24 bytes** into the `input_event` buffer  
- Performs basic error handling via exit codes  

### Handle_event
- Filters for `EV_KEY`  
- Distinguishes:
  - Press (`value = 1`)  
  - Release (`value = 0`)  
  - Hold (`value = 2`)  
- Updates:
  - `shift_flag`  
  - `cap_flag`  
  - `pressed_flag`  
- Escape key triggers a clean exit  

### Convert_to_ascii
- Uses keymap lookup tables:
  - `keymap_normal`  
  - `keymap_shift`  
- Determines if the key is a **letter** using ASCII range checks  
- Applies logic:

| Shift | Caps | Letters | Symbols |
|------|------|--------|--------|
| 0 | 0 | Normal | Normal |
| 0 | 1 | Shifted | Normal |
| 1 | 0 | Shifted | Shifted |
| 1 | 1 | Normal | Shifted |

### Log_event
- Writes a **single ASCII byte** to the log file via syscall  

### Cleanup
- Closes all open files and exits program gracefully 

---

## Build

```bash
nasm -f elf64 -g keylogger_x86_64.asm -o keylogger_x86_64.o
gcc keylogger_x86_64.o -o keylogger_x86_64
```

---
##
## Usage

Requires **root privileges**:

```bash
sudo ./keylogger
```

### Steps
1. Identify keyboard device:
   ```bash
   cat /proc/bus/input/devices
   ```
2. Locate corresponding `/dev/input/eventX`  
3. Update the device path in the source code  
4. Build and run (NASM + GCC/LD)  

---

## Future Work

- Encrypt logged keystrokes (AES)  
- Send data over a network via sockets (client/server model)  
- Background execution  
- Process injection  
