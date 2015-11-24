(* Compiler Construction - instr.ml *)
(* Samuel Sleight *)

(* Value types *)
type binop_t =
    | Add
    | Sub
    | Mul
    | Div

type fn_t = 
    | BinOp of binop_t

type io_t =
    | AsChar
    | AsInt

type value_t =
    | Int of int
    | Fn of fn_t

type value_source =
    | Const of value_t
    | BinOp of binop_t * value_source * value_source
    | Read of io_t
    | Stored of int

(* Instruction types *)
type instruction_t =
    | WriteConst of io_t * value_t
    | WriteStored of io_t * int
    | Store of value_source

(* Env type *)
type 'a env = {
    env: 'a list;
    parent: ('a env) option;
    args: string list;
    arg_values: (instruction_t list) option;
    name: string;
}

let make_env ?(parent=None) ?(name="") ?(args=[]) env = {
    env = Syntax.Env.fold (fun name value acc -> match value.Syntax.data with
        | Syntax.Int i -> `Int (name, i) :: acc
        | Syntax.Char c -> `Int (name, int_of_char c) :: acc
        | Syntax.Ident n -> `Ident (name, n) :: acc
        | Syntax.String s -> `String (name, s) :: acc
        | Syntax.Function (a, p) -> `Fn (name, a, p) :: acc
    ) env [];
    parent = parent;
    args = args;
    arg_values = None;
    name = name;
}

(* Result type *)
type result_fn = {
    code: instruction_t list;
    args: int
}

module Fns = Map.Make(String)

(* Stringify *)
let string_of_binop = function
    | Add -> "Add"
    | Sub -> "Sub"
    | Mul -> "Mul"
    | Div -> "Div"

let string_of_value = function
    | Int i -> string_of_int i
    | Fn (BinOp op) -> string_of_binop op

let rec string_of_value_source = function
    | Const v -> string_of_value v
    | BinOp (op, x, y) -> string_of_binop op ^ "[" ^ string_of_value_source x ^ ":" ^ string_of_value_source y ^ "]"
    | Read AsChar -> "Read[Char]"
    | Stored n -> "Stored[" ^ string_of_int n ^ "]"

let string_of_instr = function
    | WriteConst (AsChar, v) -> "[Write[Char:" ^ string_of_value v ^ "]]"
    | WriteStored (AsChar, v) -> "[Write[Char:Stored[" ^ string_of_int v ^ "]]]"
    | WriteConst (AsInt, v) -> "[Write[Int:" ^ string_of_value v ^ "]]"
    | WriteStored (AsInt, v) -> "[Write[Int:Stored[" ^ string_of_int v ^ "]]]"
    | Store v -> "[Store " ^ string_of_value_source v ^ "]"

let string_of_fn name fn = begin
    let buf = Buffer.create 20 in
    Buffer.add_string buf (name ^ ":" ^ string_of_int fn.args ^ ":");
    List.iter (fun instr -> Buffer.add_string buf (string_of_instr instr)) fn.code;
    Buffer.add_string buf "\n";
    Buffer.contents buf;
end

let string_of_fns fns = begin
    let buf = Buffer.create 50 in
    Fns.iter (fun name fn -> Buffer.add_string buf (string_of_fn name fn)) fns;
    Buffer.contents buf
end

(* Impl *)
let push_string values str = begin
    let ls = ref [] in
    String.iter (fun c -> ls := Const (Int (int_of_char c)) :: !ls) str;
    (List.rev !ls) @ values
end

let apply_binop values op x y = match (op, x, y) with
    | (Add, Const (Int x), Const (Int y)) -> Const (Int (x + y)) :: values
    | (Sub, Const (Int x), Const (Int y)) -> Const (Int (x - y)) :: values
    | (Mul, Const (Int x), Const (Int y)) -> Const (Int (x * y)) :: values
    | (Div, Const (Int x), Const (Int y)) -> Const (Int (x / y)) :: values

    | _ -> BinOp (op, x, y) :: values

let generate_instrs opt_flags code =
    let errors = ref [] in
    let result = ref Fns.empty in

    let rec generate_function instrs values env stored = function
        | [] -> List.rev instrs
        | exp_block :: code -> begin match exp_block.Syntax.data with
            (* Basic Values *)
            | Syntax.Value (Syntax.Int i) -> generate_function instrs (Const (Int i) :: values) env stored code
            | Syntax.Value (Syntax.Char c) -> generate_function instrs (Const (Int (int_of_char c)) :: values) env stored code
            | Syntax.Value (Syntax.String s) -> generate_function instrs (push_string values s) env stored code

            (* Binary Operators *)
            | Syntax.Op Syntax.Plus -> generate_function instrs (Const (Fn (BinOp Add)) :: values) env stored code
            | Syntax.Op Syntax.Minus -> generate_function instrs (Const (Fn (BinOp Sub)) :: values) env stored code
            | Syntax.Op Syntax.Times -> generate_function instrs (Const (Fn (BinOp Mul)) :: values) env stored code
            | Syntax.Op Syntax.Divide -> generate_function instrs (Const (Fn (BinOp Div)) :: values) env stored code

            (* Application *)
            | Syntax.Apply Syntax.Full -> begin match values with
                | Const (Fn (BinOp op)) :: rest -> begin match rest with
                    | x :: y :: rest -> generate_function instrs (apply_binop rest op x y) env stored code
                    | _ -> begin
                        errors := Errors.not_enough_args exp_block.Syntax.location :: !errors;
                        generate_function instrs values env stored code
                    end
                end
            end

            (* Read *)
            | Syntax.Read Syntax.AsChar -> generate_function instrs (Read AsChar :: values) env stored code
            | Syntax.Read Syntax.AsInt -> generate_function instrs (Read AsInt :: values) env stored code

            (* Write *)
            | Syntax.Write Syntax.AsChar -> begin match values with
                | Const value :: _ -> generate_function (WriteConst (AsChar, value) :: instrs) values env stored code
                | Stored n :: _ -> generate_function (WriteStored (AsChar, n) :: instrs) values env stored code
                | value :: rest -> generate_function (WriteStored (AsChar, stored) :: Store value :: instrs) (Stored stored :: rest) env (stored + 1) code
            end

            | Syntax.Write Syntax.AsInt -> begin match values with
                | Const value :: _ -> generate_function (WriteConst (AsInt, value) :: instrs) values env stored code
                | Stored n :: _ -> generate_function (WriteStored (AsInt, n) :: instrs) values env stored code
                | value :: rest -> generate_function (WriteStored (AsInt, stored) :: Store value :: instrs) (Stored stored :: rest) env (stored + 1) code
            end
        end
    in

    let fn = generate_function [] [] (make_env code.Syntax.env) 0 code.Syntax.code in

    if !errors = [] then
        Errors.Ok (Fns.add "" { code=fn; args=0 } !result)
    else
        Errors.Err !errors
