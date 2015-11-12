(* Compiler Construction - codegen.ml *)
(* Samuel Sleight *)

module S = Set.Make(String)

let rec idx item = function
    | [] -> 0
    | hd::tl -> if item = hd then 0 else 1 + (idx item tl)

let generate_code instrs = 
    let asm = Buffer.create 1024 in
    let used_fns = ref S.empty in

    let generate_code code = 
        let push_queue = Queue.create () in

        let arg_idx item =
            let i = idx item code.Instr.args in
            ((List.length code.Instr.args) - i) * 8
        in

        let generate_expr = function
            | Instr.PushConst (Instr.Int i) -> Queue.push (`Int i) push_queue
            | Instr.PushArg name -> Queue.push (`Arg (arg_idx name)) push_queue
            | Instr.PushFn (Instr.BinOp Instr.Add) -> begin
                Queue.push (`Int 2) push_queue;
                Queue.push (`Fn "add") push_queue;
                used_fns := S.add "add" !used_fns
            end

            | Instr.PushFn (Instr.Named s) -> begin
                Queue.push (`Int (List.length (Instr.Fns.find s instrs).Instr.args)) push_queue;
                Queue.push (`Fn s) push_queue;
            end

            | other -> begin
                if not (Queue.is_empty push_queue) then begin
                    Buffer.add_string asm (Asm.push_block push_queue);
                    Queue.clear push_queue;
                end;

                begin match other with
                    | Instr.Apply Instr.Full -> Buffer.add_string asm (Asm.apply_block ())
                end;
            end
        in

        let stack = Stack.create () in
        Stack.iter (fun item -> Stack.push item stack) code.Instr.code;
        Stack.iter generate_expr stack;

        if not (Queue.is_empty push_queue) then begin
            Buffer.add_string asm (Asm.push_block push_queue);
            Queue.clear push_queue;
        end;
    in

    let generate_function name code =
        if name = "" then begin 
            Buffer.add_string asm Asm.main_begin;
            generate_code code;
            Buffer.add_string asm Asm.debug_end;
            Buffer.add_string asm Asm.main_end;
        end else begin
            Buffer.add_string asm (Asm.function_begin name);
            generate_code code;
            Buffer.add_string asm (Asm.function_end (List.length code.Instr.args))
        end
    in

    Buffer.add_string asm Asm.data_segment;
    Instr.Fns.iter generate_function instrs;
    S.iter (fun op -> Buffer.add_string asm (Asm.op_block op)) !used_fns;

    Errors.Ok (Buffer.contents asm)