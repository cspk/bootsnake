bits 16
org 0x7C00

bootsect_sz equ 512
boot_sign_sz equ 2

jmp $; stub loop

; Make executable be 512 bytes exactly. Essential for making it bootable.
times (bootsect_sz - boot_sign_sz) - ($ - $$) db 0
dw 0xAA55; boot signature
