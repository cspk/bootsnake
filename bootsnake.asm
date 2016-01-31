bits 16
org 0x7C00

%include "bios.inc"

bootsect_sz equ 512
boot_sign_sz equ 2

video_mem_segment equ 0xB800
screen_rows equ 25
screen_cols equ 80

kbd_int equ 0x09
ioport_kbd equ 0x60
ioport_pic equ 0x20
pic_eoi equ 0x20; end of interrupt command code

; snake segment is 2-byte long: byte 1 - segment row, byte 2 - segment column
snake_segments equ 0x0500; 0x0500-0x7BFF guaranteed to be free
snake_head_init_row equ screen_rows / 2
snake_head_init_col equ screen_cols / 2

main:
	; hide cursor
	mov ah, bios_video_cursor_shape_fn
	mov ch, 0x20; bits 6:5 == 01 - cursor invisible
	int bios_video_int

	; setup video memory
	mov ax, video_mem_segment
	mov es, ax

	; setup keyboard interrupt service routine
	cli; disable interrupts
	mov word [kbd_int * 4], kbd_isr; write ISR offset to IVT
	mov word [kbd_int * 4 + 2], cs; write segment containing ISR
	sti; enable interrupts

	call snake_init

	push '#'
	call snake_print
	add sp, 2
jmp $

kbd_isr:
	push ax

	in al, ioport_kbd; read from keyboard io port
	mov al, pic_eoi
	out ioport_pic, al; acknowledge interrupt to PIC

	pop ax
iret

snake_init:
	mov dl, snake_head_init_col; column number
	mov bx, 0; offset from "snake_segments" label
	mov ax, [snake_segment_count]
	shl ax, 1; bx is incremented by 2 each time in loop, so multiply by two
.loop:
	mov byte [snake_segments + bx + 0], snake_head_init_row
	mov byte [snake_segments + bx + 1], dl

	inc dx
	add bx, 2

	cmp bx, ax
		jne .loop
ret

print_char: ; argument push order: row, col, char
	push bp
	mov bp, sp
	push ax
	push bx

	; desired char position = (row * screen_cols + col)
	mov ax, screen_cols
	mul byte [bp + 8]
	add ax, [bp + 6]

	; Multiplication by 2, needed because the video memory consists of words
	; where the first byte is character attribute and the second is the char
	; itself. We're not interested in any attributes, just place the character
	; in desired place.
	shl ax, 1

	mov bx, ax
	mov al, [bp + 4]
	mov [es:bx], al

	pop bx
	pop ax
	pop bp
ret

snake_print:
	push bp
	mov bp, sp
	pusha

	mov bx, 0
.loop:
	mov al, [snake_segments + bx + 0]
	mov dl, [snake_segments + bx + 1]
	mov cx, [snake_segment_count]
	shl cx, 1

	push ax
	push dx
	push word [bp + 4]
	call print_char
	add sp, 6

	add bx, 2
	cmp bx, cx
		jne .loop

	popa
	pop bp
ret

snake_segment_count: dw 4

; Make executable be 512 bytes exactly. Essential for making it bootable.
times (bootsect_sz - boot_sign_sz) - ($ - $$) db 0
dw 0xAA55; boot signature
