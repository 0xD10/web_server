.intel_syntax noprefix
.section .data 
.section .text
.globl _start

_start:
	push rbp
	mov rbp, rsp
	sub rsp, 2048

	# Socket Syscall
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	mov rax, 41
	syscall
	
	# Save socket_fd
	mov [rsp+16], rax

	# Create struct sockaddr
	mov word ptr [rsp], 2
	mov word ptr [rsp+2], 0x5000
	mov dword ptr [rsp+4], 0
	mov qword ptr [rsp+8], 0

	# Bind Syscall
	mov rdi, [rsp+16]
	mov rsi, rsp
	mov rdx, 16
	mov rax, 49
	syscall

	# Listen Syscall
	mov rdi, [rsp+16]
	xor rsi, rsi
	mov rax, 50
	syscall
	
	# Manually write in stack the response msg
	mov rax, 0x302e312f50545448
	mov qword ptr [rsp+32], rax 	
	mov rax, 0x0d4b4f2030303220
	mov qword ptr [rsp+40], rax
	mov rax, 0x0a0d0a
	mov qword ptr [rsp+48], rax

parent_process:
	# Accept Syscall
	mov rdi, [rsp+16]
	xor rsi, rsi
	xor rdx, rdx
	mov rax, 43
	syscall	
	
	# Save socket fd
	mov [rsp+24], rax

	# Fork Syscall
	mov rax, 57
	syscall	
	
	cmp rax, 0
	je child_process
	
	# Close Syscall
	mov rdi, [rsp+24]
	mov rax, 3
	syscall

	jmp parent_process

child_process:
	# Close Syscall
	mov rdi, [rsp+16]
	mov rax, 3
	syscall

	# Read Syscall 
	# we read from the accepted connection here
	mov rdi, [rsp+24]
	lea rsi, [rsp+104]
	mov rdx, 512
	mov rax, 0
	syscall
	
	# Save size of the request msg
	mov [rsp+1648], rax
	
	# Check GET/POST request
	mov r8, 104
	mov al, [rsp+r8]
	cmp al, 80
	je post_request_parse
	
	# GET request filename parse
	mov r8, 108
	mov r9, 56
	mov al, [rsp+r8]
	cmp al, 32
	je continue_get
	get_parse_filename:
		mov al, [rsp+r8]
		mov byte ptr [rsp+r9], al
		inc r8
		inc r9
		mov al, [rsp+r8]
		cmp al, 32
	jne get_parse_filename
	inc r9
	mov byte ptr [rsp+r9], 10
	continue_get:
	
	# Open filename we got from client offset+312
	lea rdi, [rsp+56]
	mov rsi, 0
	mov rdx, 0
	mov rax, 2
	syscall
	
	# Save fd of file we opened
	mov [rsp+88], rax	
	
	# Read from filename
	mov rdi, [rsp+88]
	lea rsi, [rsp+616]
	mov rdx, 1024
	mov rax, 0
	syscall	
	
	# Save filesize 
	mov [rsp+96], rax

	# Close file from client
	mov rdi, [rsp+88]
	mov rax, 3
	syscall	
	
	# Write Syscall 
	# write the response to the fd that connected to our server
	mov rdi, [rsp+24]
	lea rsi, [rsp+32]
	mov rdx, 19
	mov rax, 1
	syscall	

	# Write file from client
	mov rdi, [rsp+24]
	lea rsi, [rsp+616]
	mov rdx, [rsp+96]
	mov rax, 1
	syscall

	# Close Syscall
	mov rdi, [rsp+24]
	mov rax, 3
	syscall
	jmp continue

post_request_parse:
	
	# POST request filename parse
	mov r8, 109
	mov r9, 56
	mov al, [rsp+r8]
	cmp al, 32
	je continue_post
	post_parse_filename:
		mov al, [rsp+r8]
		mov byte ptr [rsp+r9], al
		inc r8
		inc r9
		mov al, [rsp+r8]
		cmp al, 32
	jne post_parse_filename
	inc r9
	mov byte ptr [rsp+r9], 10
	
	continue_post:
	
	# Parse content length header
	mov r8, 104
	mov rbx, 0x2d746e65746e6f43
	mov rcx, 0x203a6874676e654c
	loop_string_1:
		mov rax, [rsp+r8]
		inc r8
		cmp rax, rbx
		jne loop_string_1
		dec r8
		add r8, 8
		mov rax, [rsp+r8]
		cmp rax, rcx
		je exit_loop_string_1
		cmp r8, 606
		jl loop_string_1
	exit_loop_string_1:
	
	xor rax, rax
	add r8, 8
	string_to_int:
    	movzx rcx, byte ptr [rsp+r8]
    	cmp rcx, '0'
    	jb exit_parse
    	cmp rcx, '9'
    	ja exit_parse
    	sub rcx, '0'
    	imul rax, rax, 10
    	add rax, rcx
    	inc r8
    jmp string_to_int

	exit_parse:
    mov qword ptr [rsp+1640], rax
	
	# Open filename 
  	lea rdi, [rsp+56];
  	mov rsi, 65;
  	mov rdx, 0x1FF;
	mov rax, 2
  	syscall;

	# Save file fd
	mov [rsp+88], rax
	
	# Calculate offset of file data
	mov r8, [rsp+1648]
	mov r9, [rsp+1640]
	sub r8, r9
	
	# Write file
	mov rdi, [rsp+88]
	lea rsi, [rsp+104+r8]
	mov rdx, [rsp+1640]
	mov rax, 1
	syscall	

	# Close Syscall
    mov rdi, [rsp+88]
    mov rax, 3
    syscall
    
	# Write Syscall
    # write the response to the fd that connected to our server
    mov rdi, [rsp+24]
    lea rsi, [rsp+32]
    mov rdx, 19
    mov rax, 1
    syscall

	jmp continue
	
continue:

	# Restore Stack
	mov rsp, rbp
	pop rbp
	
	# Exit Syscall
    mov rdi, 0
    mov rax, 60
    syscall


#################
# Data in Stack # 
#################
# [rsp+0] 16-bytes for the struct sockaddr [2-bytes for sin_family] [2-bytes for port number] [4-bytes for ipv4 address] [8-bytes zeros]
# [rsp+16] 8-bytes for our socket file descriptor
# [rsp+24] 8-bytes for our client socket file descriptor
# [rsp+32] 24-bytes for our response message 
# [rsp+56] 32-bytes for the filename we extracted from client message
# [rsp+88] 8-bytes for the fd of file
# [rsp+96] 8-bytes for filesize
# [rsp+104] 512-bytes for our client header msg
# [rsp+616] 1024-bytes for buffer
# [rsp+1640] 8-bytes content length header
# [rsp+1648] 8-bytes size of client msg
# [rsp+1656]
