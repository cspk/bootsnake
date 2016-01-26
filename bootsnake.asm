bits 16
org 0x7C00

%include "bios.inc"

bootsect_sz equ 512
boot_sign_sz equ 2

; hide the cursor
mov ah, bios_video_cursor_shape_fn
mov ch, 0x20; bits 6:5 == 01 - cursor invisible
int bios_video_int

jmp $; stub loop

; Make executable be 512 bytes exactly. Essential for making it bootable.
times (bootsect_sz - boot_sign_sz) - ($ - $$) db 0
dw 0xAA55; boot signature
