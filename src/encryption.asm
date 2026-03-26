; encryption.asm
; Author : Samuel Gould
; Date: 2026-03-17
; Description:
; - Provides functions required for AES-128 encryption 
; Notes:
; - Will read buffer and encrypt in 16 byte increments
; Functions:
;   aes_encrypt 
;   aes_keyexpansion
;   add_round_key 
;   sub_bytes 
;   shift_rows 
;   mix_columns 
;   g_func

%include "common.inc"
global aes_encrypt
global aes_key_expansion

; - - - Initialized Data - - -
section .data
s_block db 0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16

round_const db 0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36 ; 0x00 unused

; - - - Uninitialized Data - - -
section .bss
  plaintext_block resq 1  ; Holds affective addres of original plaintext 
  temp_block resb 16 
  temp_word resb 4 

; - - - MACROS - - -

; Multiply byte by 2 in GF(2^8)
; Works on dl and stores result in dl 
%macro XTIME 0  
  shl dl, 1 
  jnc %%no_wrap   ; if carry, we know last bit was set
    xor dl, 0x1b  
  %%no_wrap: 
  %endmacro 

; - - - ENDMAC - - -

; - - - Library procedures - - -
section .text

; rdi = pointer to plaintext packet buffer
; rsi = pointer to expanded key
; rdx = pointer to encrypted packet buffer
aes_encrypt:

  ; sub_byte(rdi=state)
  ; shift_rows(rdi=state) 
  ; mix_columns(rdi=state)
  ; add_round_key(rdi=state, rsi=round_key)

  push rax
  push rbx 
  push rcx 
  push rdx

  ; Round 0
  call add_round_key
  lea rsi, [rsi + 16]   ; Move pointer 16 bytes later

  ; Rounds 1-9
  mov rcx, 1
  .round_loop:
    
    call sub_bytes 
    call shift_rows 
    call mix_columns
    call add_round_key

    lea rsi, [rsi + 16]   ; Move pointer 16 bytes later 

    inc rcx
    cmp rcx, 10
      jl .round_loop

  ; Round 10 
  call sub_bytes
  call shift_rows 
  call add_round_key

  ; Load encrypted string into rdx
  mov rax, qword [rdi]
  mov [rdx], rax
  mov rax, qword [rdi + 8]
  mov [rdx + 8], rax

  pop rdx 
  pop rcx 
  pop rbx 
  pop rax 

  ret

; rsi - pointer to key
; rdi - pointer to expanded key
aes_key_expansion:
  
  push rax 
  push rbx 
  push rcx 
  push rdx
  
  ; Load first 4 words into expanded key
  mov rax, qword [rsi] 
  mov [rdi], rax 
  mov rax, qword [rsi + 8]
  mov [rdi + 8], rax

  xor rcx, rcx 
  xor rdx, rdx

  lea rsi, temp_word        ; temp = col[0] for use in g_func

  mov rcx, 4  ; # of **words** generated 
  mov rdx, 0  ; # of rounds 

  ; generate remaining words 
  .expansion_loop:
    mov eax, dword [rdi + (rcx-1)*4]    ; at correct /4 offset (0-indexed)
    mov [rsi], eax
    

    ; is it 4th word?
    ; bitwise AND with 0...0011
    ; if ZF=1, last two bits were 00, so divisible
    test rcx, 3 
      jnz .not_divisible
      inc rdx               ; 1 round has passed
      call g_func ; rsi = temp word buffer, rdx = round count 

    .not_divisible:
    mov eax, dword [rsi]                ; temp word into eax 
    xor eax, dword [rdi + (rcx-4)*4]    ; xor with word 4 positions back 
    mov [rdi + rcx*4], eax              ; store in expanded key at current position

    inc rcx
    cmp rcx, 44 
      jl .expansion_loop

  pop rdx 
  pop rcx 
  pop rbx 
  pop rax

  ret

; - - - AES Tranformations - - -

; XOR source block with destination block (effectively matrix addition)
; rdi = state
; rsi = round_key
; 
; Returns: XORed state in rdi
add_round_key:
  push rax 
  push rbx 

  mov rax, qword [rdi]
  mov rbx, qword [rsi]
  xor rax, rbx 
  mov [rdi], rax 
  mov rax, qword [rdi + 8]
  mov rbx, qword [rsi + 8]
  xor rax, rbx
  mov [rdi + 8], rax 

  pop rbx 
  pop rax
  ret 

; Substitutes each byte in state via s-box lookup
; rdi = state 
; 
; Returns: substituted state in rdi 
sub_bytes:
  push rax 
  push rcx

  mov rcx, 16 
  .sub_loop:
    ; x-axis = x0 (mem * 0-15)
    ; y-axis = 0x (mem + 0-15)
  
    mov al, byte [ rdi + rcx - 1] ; Subs in reverse order
    movzx rax, al                 ; index at rax location
    mov al, byte [s_block + rax]
    mov [rdi + rcx - 1], al 

    dec rcx 
      jnz .sub_loop 

    pop rcx 
    pop rax 
  ret 

; Shifts rows of state 
; row1 = no change. row1 = rol1, row2 = rol2, row 3 = rol3 (equ to ror 1)  // (opposite for little endian)
; rdi = state
; 
; Returns: shifted state
shift_rows:
  push rax
  push rbx
  push rcx
  push rdx

  ; row 1
  mov al, [rdi+1]
  mov bl, [rdi+5]
  mov cl, [rdi+9]
  mov dl, [rdi+13]

  mov [rdi+1], bl
  mov [rdi+5], cl
  mov [rdi+9], dl
  mov [rdi+13], al

  ; row 2
  mov al, [rdi+2]
  mov bl, [rdi+6]
  mov cl, [rdi+10]
  mov dl, [rdi+14]

  mov [rdi+2], cl
  mov [rdi+6], dl
  mov [rdi+10], al
  mov [rdi+14], bl

  ; row 3
  mov al, [rdi+3]
  mov bl, [rdi+7]
  mov cl, [rdi+11]
  mov dl, [rdi+15]

  mov [rdi+3], dl
  mov [rdi+7], al
  mov [rdi+11], bl
  mov [rdi+15], cl

  pop rdx
  pop rcx 
  pop rbx
  pop rax
  ret 

; Perform arithmetic required to substitue bytes with GF(2^8)
; rdi = state block
; 
; Returns: substituted state block 
mix_columns:

  push rax 
  push rbx 
  push rcx 
  push rdx
  push rsi

  xor rcx, rcx 

  .col_loop:

    lea rsi, [rdi + rcx*4]      ; pointer to column

    mov al, byte [rsi]              ; t = b[0] ^ b[1] ^ b[2] ^ b[3]
    xor al, byte [rsi + 1]
    xor al, byte [rsi + 2]
    xor al, byte [rsi + 3]

    mov bl, byte [rsi]              ; col[0] stored for xtime

    ; col[n] ^= t ^ xtime(col[n] ^ col[n+1])

    mov dl, byte [rsi]
    xor dl, byte [rsi + 1]
    XTIME 
    xor dl, al 
    xor dl, byte [rsi]
    mov [rsi], byte dl

    ; col[1]
    mov dl, byte [rsi + 1]
    xor dl, byte [rsi + 2]
    XTIME 
    xor dl, al 
    xor dl, byte [rsi + 1]
    mov [rsi + 1], byte dl
    
    ; col[2]
    mov dl, byte [rsi + 2]
    xor dl, byte [rsi + 3]
    XTIME 
    xor dl, al 
    xor dl, byte [rsi + 2]
    mov [rsi + 2], byte dl
    
    ; col[3]
    mov dl, byte [rsi + 3]
    xor dl, bl
    XTIME 
    xor dl, al 
    xor dl, byte [rsi + 3]
    mov [rsi + 3], byte dl

    inc rcx
    cmp rcx, 4
      jl .col_loop

  pop rsi
  pop rdx
  pop rcx 
  pop rbx 
  pop rax

  ret 

; - - - Key Expansion Function(s) - - -

; Rotate word left by 1 byte, apply s-box to all 4 bytes, XOR first byte with round constant
; rsi = temp word buffer 
; rdx = round #
; 
; Returns: word in rdi processed by g function
g_func:

  push rax 
  push rcx 

  mov eax, dword [rsi]    ; rotate left 1 
  ror eax, 8              ; little endian requires reverse rotation
  mov dword [rsi], eax 

  ; s-box substitution for each byte 
  xor rcx, rcx 
  .sub_loop:
    mov al, byte [rsi + rcx]
    movzx rax, al 
    mov al, byte [s_block + rax]
    mov [rsi + rcx], al 
    inc rcx 
    cmp rcx, 4 
      jb .sub_loop

  ; xor byte 1 with round_const
  mov al, byte [rsi]              
  xor al, byte [round_const + rdx]
  mov [rsi], al 

  pop rcx 
  pop rax 
  ret 
