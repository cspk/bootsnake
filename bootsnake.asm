bits 16
org 0x7C00

%include "bios.inc"

bootsect_sz equ 512
boot_sign_sz equ 2

video_mem_segment equ 0xB800

kbd_int equ 0x09
ioport_kbd equ 0x60
ioport_pic equ 0x20
pic_eoi equ 0x20; end of interrupt command code

main:
	; hide the cursor
	mov ah, bios_video_cursor_shape_fn
	mov ch, 0x20; bits 6:5 == 01 - cursor invisible
	int bios_video_int

	; setup video memory
	mov ax, video_mem_segment
	mov es, ax

	; setup keyboard interrupt service routine
	cli; disable interrupts
	mov word [kbd_int * 4], kbd_isr; write the offset of the ISR to the IVT
	mov word [kbd_int * 4 + 2], cs; write the segment containing the ISR
	sti; enable interrupts
jmp $

kbd_isr:
	push ax

	in al, ioport_kbd; read from keyboard io port
	mov al, pic_eoi
	out ioport_pic, al; acknowledge the interrupt to the PIC

	pop ax
iret

; Make executable be 512 bytes exactly. Essential for making it bootable.
times (bootsect_sz - boot_sign_sz) - ($ - $$) db 0
dw 0xAA55; boot signature
