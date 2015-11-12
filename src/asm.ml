(* Compiler Construction - asm.ml *)
(* Samuel Sleight *)

let unique_id = let prev = ref (-1) in (fun () -> prev := !prev + 1; !prev) 

let data_segment = 
"    .data
int_format_str:
    .asciz \\\"%d\\n\\\"
    .align  8
stack_size:
    .quad   1024
    .align 8
stack_pos:
    .quad   0
    .comm   stack, 8, 8
    .text
"

let main_begin =
"    .globl main
main:
    movq    stack_size(%rip), %rdi
    call    malloc
    movq    %rax, stack(%rip)
"

let debug_end =
"    movq    stack_pos(%rip), %rax
    subq    \\$1, %rax
    movq    %rax, stack_pos(%rip)
    movq    stack(%rip), %rdx
    movq    (%rdx, %rax, 8), %rsi
    movq    \\$int_format_str, %rdi
    movq    \\$0, %rax
    call    printf
"

let main_end =
"    movq    stack(%rip), %rdi
    call    free
    movl    \\$0, %eax
    ret
"

let function_begin name =
name ^ ":
"

let function_end args = 
"    ret
"

let push_block_begin =
"    movq    stack_pos(%rip), %rax
    movq    stack(%rip), %rdx
"

let push_block_item n = function
    | `Int i -> 
"    movq    \\$" ^ (string_of_int i) ^ ", " ^ (string_of_int n) ^ "(%rdx, %rax, 8)
"

    | `Arg i -> 
"    movq    " ^ (string_of_int (i + 8)) ^ "(%rsp), %r9
    movq    %r9, " ^ (string_of_int n) ^ "(%rdx, %rax, 8)
"

    | `Fn s -> 
"    movq    \\$" ^ s ^ ", " ^ (string_of_int n) ^ "(%rdx, %rax, 8)
"

let push_block_end n = 
"    leaq    " ^ (string_of_int n) ^ "(%rax), %rax
    movq    %rax, stack_pos(%rip)
"

let push_block stack =
    let next_n = let prev = ref (-1) in (fun () -> prev := !prev + 1; !prev * 8) in
    let buf = Buffer.create 100 in
    Buffer.add_string buf push_block_begin;
    Queue.iter (fun item -> Buffer.add_string buf (push_block_item (next_n ()) item)) stack;
    Buffer.add_string buf (push_block_end (Queue.length stack));
    Buffer.contents buf

let apply_block () = 
    let n = string_of_int (unique_id ()) in
"    movq    stack_pos(%rip), %rax
    subq    \\$2, %rax
    movq    stack(%rip), %rdx
    movq    8(%rdx, %rax, 8), %r8
    movq    (%rdx, %rax, 8), %rcx
    movq    %rsp, %rbp
arg_loop_" ^ n ^ ":
    subq    \\$1, %rax
    subq    \\$1, %rcx
    pushq   (%rdx, %rax, 8)
    cmp     \\$0, %rcx
    jne     arg_loop_" ^ n ^ "
    movq    %rax, stack_pos(%rip)
    pushq   %rbp
    call    *%r8
    popq    %rsp
"

let op_block op =
    if op = "add" then
"add:
    movq    24(%rsp), %rsi
    addq    16(%rsp), %rsi
    movq    stack_pos(%rip), %rax
    leaq    1(%rax), %rdx
    movq    %rdx, stack_pos(%rip)
    movq    stack(%rip), %rdx
    movq    %rsi, (%rdx, %rax, 8)
" ^ (function_end 2)

    else ""