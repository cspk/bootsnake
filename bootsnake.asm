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

scancode_cursor equ 0xE0
scancode_cursor_up_pressed equ 0x48
scancode_cursor_down_pressed equ 0x50
scancode_cursor_left_pressed equ 0x4B
scancode_cursor_right_pressed equ 0x4D

; snake segment is 2-byte long: byte 1 - segment row, byte 2 - segment column
snake_segments equ 0x0500; 0x0500-0x7BFF guaranteed to be free
snake_head_init_row equ screen_rows / 2
snake_head_init_col equ screen_cols / 2

snake_direction_up equ scancode_cursor_up_pressed
snake_direction_down equ scancode_cursor_down_pressed
snake_direction_left equ scancode_cursor_left_pressed
snake_direction_right equ scancode_cursor_right_pressed

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
.loop:
	call snake_move
	call sleep_nop
	jmp .loop
jmp $

kbd_isr:
	push ax

	in al, ioport_kbd; read from keyboard io port

	cmp al, scancode_cursor_up_pressed
		je .set_direction_up
	cmp al, scancode_cursor_down_pressed
		je .set_direction_down
	cmp al, scancode_cursor_left_pressed
		je .set_direction_left
	cmp al, scancode_cursor_right_pressed
		je .set_direction_right
	jmp .out

.set_direction_up:
	cmp byte [snake_current_direction], snake_direction_down
		je .out
	jmp .set_direction
.set_direction_down:
	cmp byte [snake_current_direction], snake_direction_up
		je .out
	jmp .set_direction
.set_direction_left:
	cmp byte [snake_current_direction], snake_direction_right
		je .out
	jmp .set_direction
.set_direction_right:
	cmp byte [snake_current_direction], snake_direction_left
		je .out
	jmp .set_direction
.set_direction:
	mov [snake_current_direction], al
.out:
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

snake_move:
	push ' '
	call snake_print
	add sp, 2

	call snake_tail_update
	call snake_head_update

	push '#'
	call snake_print
	add sp, 2
ret

snake_tail_update:
	pusha

	mov ax, [snake_segment_count]
	dec ax
	shl ax, 1

	mov bx, snake_segments
	add bx, ax
.loop:
	mov ax, [bx - 2]
	mov [bx], ax
	sub bx, 2
	cmp bx, snake_segments
		jne .loop

	popa
ret

snake_head_update:
	cmp byte [snake_current_direction], snake_direction_up
		je .move_up
	cmp byte [snake_current_direction], snake_direction_down
		je .move_down
	cmp byte [snake_current_direction], snake_direction_left
		je .move_left
	cmp byte [snake_current_direction], snake_direction_right
		je .move_right
ret
.move_up:
	dec byte [snake_segments + 0]
	cmp byte [snake_segments + 0], 0
		je game_over
	call check_self_hit
ret
.move_down:
	inc byte [snake_segments + 0]
	cmp byte [snake_segments + 0], screen_rows - 1
		je game_over
	call check_self_hit
ret
.move_left:
	dec byte [snake_segments + 1]
	cmp byte [snake_segments + 1], 0
		je game_over
	call check_self_hit
ret
.move_right:
	inc byte [snake_segments + 1]
	cmp byte [snake_segments + 1], screen_cols - 1
		je game_over
	call check_self_hit
ret

check_self_hit:
	pusha

	mov ah, [snake_segments + 0]; head row
	mov al, [snake_segments + 1]; head col
	mov bx, 2; current snake segment offset
	mov dx, [snake_segment_count]
	shl dx, 1; multiply by two because we add 2 to bx each time
.loop:
	cmp ah, [snake_segments + bx + 0]
		jne .not_hit
	cmp al, [snake_segments + bx + 1]
		jne .not_hit
	jmp game_over
.not_hit:
	add bx, 2
	cmp bx, dx
		jne .loop
.out:
	popa
ret

; This is a temporary replacement for a proper sleep/delay routine. I have to
; use it because I don't know yet how to interrupt BIOS sleep routine (int 0x15,
; ah = 0x86) when a key is pressed.
sleep_nop:
	push eax

	xor eax, eax
.loop:
	nop
	inc eax
	cmp eax, 0xFFFF * 128
		je .out
	jmp .loop
.out:
	pop eax
ret

game_over:
	push '#'
	call snake_print

	mov al, [snake_segments + 0]
	mov bl, [snake_segments + 1]
	push ax
	push bx
	push 'X'
	call print_char
jmp $

snake_segment_count: dw 4
snake_current_direction: db snake_direction_left

; Make executable be 512 bytes exactly. Essential for making it bootable.
times (bootsect_sz - boot_sign_sz) - ($ - $$) db 0
dw 0xAA55; boot signature
