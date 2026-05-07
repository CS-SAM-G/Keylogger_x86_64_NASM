; socket.asm - VERSION 1
; Author: Samuel Gould
; Date: 2026-03-20
; Description:
;   NASM Linux x86-64 TCP client implemented in assembly
;   - Establishes TCP connection to remote host
;   - Sends framed packets using custom protocol
;   - Implements reconnect logic and heartbeat system
; Notes:
;   - Uses basic packet structure: [type (1)][length (2)][payload]
;   - No encryption implemented yet (placeholder for future module)
;   - Designed for local testing (VM ↔ host via NAT)
;

%include "common.inc"
global read_thread
extern socket_connected
extern socket_done
extern write_pos
extern read_pos
extern buffer 
extern BUFFER_SIZE

extern aes_key_expansion
extern aes_encrypt

; - - - INITIALIZED DATA - - -
section .data

  ; Server configuration
  server_ip db 192,168,35,1          ; Host IP (VMware NAT default gateway)
  server_port dw 9090

  ; Packet types
  HEARTBEAT_TYPE equ 1
  MESSAGE_TYPE equ 2

  ; Packet Constants 
  MAX_PACKET_SIZE equ 1024 

  ; Connection configuration
  RECONNECT_ATTEMPTS equ 3
  RECONNECT_DELAY equ 5              ; seconds
  HEARTBEAT_INTERVAL equ 10          ; seconds

  ; AES key
  key db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f 


; - - - UNINITIALIZED DATA - - -
section .bss
  sock_fd resq 1                     ; Socket file descriptor
  sockaddr_in resb 16                ; struct sockaddr_in
  packet_buffer resb MAX_PACKET_SIZE ; Protocol buffer
  fragment_flag resb 1               ; Change to fragment flag duh

  ; timespec struct for nanosleep
  ts_sec resq 1
  ts_nsec resq 1

  ; AES 
  expanded_key resb 176
  

; - - - MACROS - - -

; Create socket
; Usage: CREATE_SOCKET
; Returns: RAX = socket fd, -1 on failure
%macro CREATE_SOCKET 0
  mov rax, SYS_SOCKET
  mov rdi, AF_INET
  mov rsi, SOCK_STREAM
  xor rdx, rdx
  syscall
%endmacro

; Connect socket
; Usage: CONNECT_SOCKET
; Returns: RAX = 0 on success, -1 on failure
%macro CONNECT_SOCKET 0
  mov rax, SYS_CONNECT
  mov rdi, [sock_fd]
  lea rsi, [sockaddr_in]
  mov rdx, 16
  syscall
%endmacro

; Encrypt and send packet
; Parameters:
;   %1 = buffer
;   %2 = length
; Usage: SEND_PACKET packet_buffer
%macro SEND_PACKET 2

  mov rbx, %1                     ; Store start position
  mov rsi, expanded_key           ; Store EK for aes_encrypt function 
  mov rdi, rbx                    ; Current block pointer
  
  mov rcx, %2
  add rcx, 15         ; Forces ceiling when shr 4 (/ 16)
  shr rcx, 4

  mov rdx, rcx        ; # of blocks we're encrypting

  %%encrypt_packet:
    call aes_encrypt
    add rdi, 16
    dec rcx 
    jnz %%encrypt_packet

  mov rax, SYS_WRITE
  mov rdi, [sock_fd]
  mov rsi, rbx
  shl rdx, 4          ; bytes = blocks * 16
  syscall

%endmacro


; Close socket
%macro CLOSE_SOCKET 0
  mov rax, SYS_CLOSE
  mov rdi, [sock_fd]
  syscall
%endmacro

; Expand key 
%macro EXPAND_KEY 0
  mov rsi, key
  mov rdi, expanded_key ; do we have to move back?
  call aes_key_expansion
%endmacro 


; - - - CODE - - -
section .text
global read_thread
read_thread:
  EXPAND_KEY
  call read_init
  call connect_loop

; Initialize socket and address
read_init:

  ; Create socket
  CREATE_SOCKET
  CHECK_SYSCALL
  mov [sock_fd], rax
  mov [fragment_flag], 0

  ; Configure sockaddr_in struct
  call configure_address
  ret

; Attempt connection with retries
connect_loop:
  mov rcx, RECONNECT_ATTEMPTS

  .loop:
    CONNECT_SOCKET
    cmp rax, 0
      jge read_loop

    SLEEP RECONNECT_DELAY
    dec rcx
    cmp rcx, 0
      jne .loop

    EXIT 1

; Main communication loop
read_loop:

  mov byte [socket_connected], 1

  ; Send heartbeat packet
  call send_heartbeat

  ; Send message packet
  read_all:
  call send_message
  cmp [fragment_flag], 1 
    je read_all

  SLEEP HEARTBEAT_INTERVAL
  jmp read_loop

; - - - PACKET HANDLING - - -

; Build and send heartbeat packet
send_heartbeat:
  mov byte [packet_buffer], HEARTBEAT_TYPE
  mov word [packet_buffer + 1], 0

  SEND_PACKET packet_buffer, 3
  cmp rax, 0
    jl reconnect
  ret

; Build and send message packet
send_message:

  mov byte [packet_buffer], MESSAGE_TYPE

  call read_buffer              ; Holds number of payload bytes in RAX 
  cmp rax, 0 
    je .dont_send               ; Nothing new has been written to buffer

  ; Store payload length in header (big endian)
  xchg ah, al 
  mov [packet_buffer + 1], ax
  xchg ah, al 
  add ax, 3 
  movzx rcx, ax                 ; extend to 64-bit for SEND_PACKET

  SEND_PACKET packet_buffer, rcx
    jl reconnect
  .dont_send:
  ret

read_buffer:
  mov rax, [read_pos]
  mov rbx, [write_pos]
  xor rcx, rcx          ; counter for payload length

  cmp rax, rbx          ; check if buffer is empty
    je .buffer_empty

  lea rsi, [packet_buffer + 3]  ; Start writing after header

  .read_payload:
    mov dl, [buffer + rax]  ; load one byte from buffer 
    mov [rsi + rcx], dl
    inc rcx               ; Payload length ++

    inc rax               ; Advance read pointer
    cmp rax, BUFFER_SIZE 
      jl .no_wrap
      xor rax, rax        ; wrap around
    
    .no_wrap:
    mov [read_pos], rax
    cmp rcx, MAX_PACKET_SIZE - 3 ; Check for oversize packet - space for type and length
      jae .fragment

    cmp rax, rbx              ; Have we read everything we can?
      jne .read_payload       

    ; If we have:
    mov byte [fragment_flag], 0   ; Clear oversize oversize_flag 
    mov rax, rcx
    ret 
 
  .fragment:
    mov byte [fragment_flag], 1        ; signal overflow 
    mov rax, rcx
    ret

  .buffer_empty: 
    xor rax, rax          ; return 0 if nothing to read
    ret

; - - - SOCKET HELPERS - - -

; Configure sockaddr_in structure
configure_address:
  lea rdi, [sockaddr_in]

  ; Family
  mov word [rdi], AF_INET

  ; Port (network byte order)
  mov ax, [server_port]
  xchg al, ah
  mov [rdi + 2], ax

  ; IP address
  mov eax, [server_ip]
  mov [rdi + 4], eax

  ; Zero padding
  xor rax, rax
  mov [rdi + 8], rax
  ret

; Handle reconnect
reconnect:
  CLOSE_SOCKET
  mov byte [socket_connected], 0
  jmp connect_loop

; Cleanup / exit
read_cleanup:
  CLOSE_SOCKET
  mov byte [socket_done], 1
  EXIT 0

runtime_error:
  EXIT rax
    
