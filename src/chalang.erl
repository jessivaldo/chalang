-module(chalang).
-export([run5/2, data_maker/8, test/6, vm/6, replace/3, new_state/3, new_state/2, split/2, none_of/1, stack/1, time_gas/1]).
-record(d, {op_gas = 0, stack = [], alt = [],
	    ram_current = 0, ram_most = 0, ram_limit = 0, 
	    vars = {},  
	    funs = {}, many_funs = 0, fun_limit = 0,
	    state = [], hash_size = chalang_constants:hash_size()
	   }).
-record(state, {
	  height, %how many blocks exist so far
	  slash = 0 %is this script being run as a solo_stop transaction, or a slash transaction?
	 }).
stack(D) -> D#d.stack.
time_gas(D) -> D#d.op_gas.
%space_gas(D) -> D#d.ram_current.
new_state(Height, Slash, _) ->
    new_state(Height, Slash).
new_state(Height, Slash) ->
    #state{height = Height, 
	   slash = Slash}.
-define(int, 0).
-define(binary, 2).
-define(print, 10).
-define(return, 11).
-define(nop, 12).
-define(fail, 13).
-define(drop, 20).
-define(dup, 21).
-define(swap, 22).
-define(tuck, 23).
-define(rot, 24).
-define(ddup, 25).
-define(tuckn, 26).
-define(pickn, 27).
-define(to_r, 30).
-define(from_r, 31).
-define(r_fetch, 32).
-define(hash, 40).
-define(verify_sig, 41).
-define(add, 50).
-define(remainder, 57).
-define(eq, 58).
-define(caseif, 70).
-define(else, 71).
-define(then, 72).
-define(bool_flip, 80).
-define(bool_and, 81).
-define(bool_or, 82).
-define(bool_xor, 83).
-define(bin_and, 84).
-define(bin_or, 85).
-define(bin_xor, 86).
-define(stack_size, 90).
-define(height, 94).
-define(gas, 96).
-define(ram, 97).
-define(many_vars, 100).
-define(many_funs, 101).
-define(define, 110).
-define(fun_end, 111).
-define(recurse, 112).
-define(call, 113).
-define(set, 120).
-define(fetch, 121).
-define(cons, 130).
-define(car, 131).
-define(nil, 132).
-define(append, 134).
-define(split, 135).
-define(reverse, 136).
-define(is_list, 137).


-define(int_bits, 32). %this isn't an opcode, it is for writing this same page. chalang.erl

%op_gas limits our program in time.
%ram_gas limits our program in space.
make_tuple(X, Size) ->
    list_to_tuple(make_list(X, Size, [])).
make_list(_, 0, X) -> X;
make_list(X, Size, L) -> 
    make_list(X, Size - 1, [X|L]).
vm(Script, OpGas, RamGas, Funs, Vars, State) ->
    X = test(Script, OpGas, RamGas, Funs, Vars, State),
    X#d.stack.
test(Script, OpGas, RamGas, Funs, Vars, State) ->
    D = #d{op_gas = OpGas,
	   ram_limit = RamGas,
	   vars = make_tuple(e, Vars),
	   funs = #{},
	   fun_limit = Funs,
	   ram_current = size(Script), 
	   state = State},
    %compiler_chalang:print_binary(Script),
    %io:fwrite("\nrunning a script =============\n"),
    %disassembler:doit(Script),
    run2([Script], D).
    %io:fwrite("\n"),

						%io:fwrite("oGas, stack, alt, ram_current, ram_most, ram_limit, vars, funs, many_funs, fun_limit\n"),
    %X#d.stack.

%run takes a list of bets and scriptpubkeys. Each bet is processed seperately by the RUN2, and the results of each bet is accumulated together to find the net result of all the bets.
data_maker(OpGas, RamGas, Vars, Funs, ScriptSig, SPK, State, HashSize) ->
    #d{op_gas = OpGas, 
       ram_limit = RamGas, 
       vars = make_tuple(e, Vars),
       funs = #{},
       fun_limit = Funs,%how many functions can be defined.
       ram_current = size(ScriptSig) + size(SPK),
       state = State, 
       hash_size = HashSize}.
    
%run2 processes a single opcode of the script. in comparison to run3/2, run2 is able to edit more aspects of the RUN2's state. run2 is used to define functions and variables. run3/2 is for all the other opcodes. 
run5(A, D) ->
    true = balanced_f(A, 0),
    run2([A], D).
run2(_, {error, S}) ->
    io:fwrite("had an error\n"),
    io:fwrite(S),
    io:fwrite("\n"),
    {error, S};
run2(_, D) when D#d.op_gas < 0 ->
    io:fwrite("out of time"),
    D = ok,
    {error, "out of time"};
run2(_, D) when D#d.ram_current > D#d.ram_limit ->
    io:fwrite("Out of space. Limit was: "),
    io:fwrite(integer_to_list(D#d.ram_limit)),
    io:fwrite("\n"),
    D = ok,
    {error, "out of space"};
run2(A, D) when D#d.ram_current > D#d.ram_most ->
    run2(A, D#d{ram_most = D#d.ram_current});
run2([<<>>|T], D) -> run2(T, D);
run2([], D) -> D;
run2([<<?binary:8, H:32, Script/binary>>|Tail], D) ->
    T = D#d.stack,
    X = H * 8,
    <<Y:X, Script2/binary>> = Script,
    NewD = D#d{stack = [<<Y:X>>|T],
	       ram_current = D#d.ram_current + 1,%1 for the 1 list link added to ram.
	       op_gas = D#d.op_gas - H},
    %<<Temp:8, _/binary>> = Script2,
    run2([Script2|Tail], NewD);
run2([<<?int:8, V:?int_bits, Script/binary>>|T], D) ->
    NewD = D#d{stack = [<<V:?int_bits>>|D#d.stack],
	       ram_current = D#d.ram_current + 1,
	       op_gas = D#d.op_gas - 1},
    run2([Script|T], NewD);
run2([<<?caseif:8, Script/binary>>|Tail], D) ->
    [<<B:32>>|NewStack] = D#d.stack,
    {Case1, Rest, _} = split_if(?else, Script),
    {Case2, Rest2, _} = split_if(?then, Rest),
    Steps = size(Case1) + size(Case2),
    {Case, SkippedSize} = 
	case B of
	    0 -> %false
		{Case2, size(Case1)};
	    _ ->
		{Case1, size(Case2)}
	end,
    NewD = D#d{ stack = NewStack,
		ram_current = D#d.ram_current - SkippedSize - 1, % +1 for new list link in Script. -2 for the else and then that are deleted.
	       op_gas = D#d.op_gas - Steps},
    run2([Case|[Rest2|Tail]], NewD);
run2([<<?call:8, ?fun_end:8, Script/binary>>|Tail], D) ->
    run2([<<?call:8, Script/binary>>|Tail], D); %tail call optimization
run2([<<?call:8>>|[<<?fun_end:8>>|Tail]], D) ->
    run2([<<?call>>|Tail], D); %tail call optimization
run2([<<?call:8, Script/binary>>|Tail], D) ->
    case D#d.stack of 
        [H|T] ->
            case maps:find(H, D#d.funs) of
                error -> {error, "called undefined function"};
                {ok, Definition} ->
                    S = size(Definition),
                    NewD = D#d{op_gas = D#d.op_gas - S - 10,
                               ram_current = D#d.ram_current + S + 2,%-1 for call, +1 for fun_end, +2 for 2 new list links.
                               stack = T},
                    run2([Definition|[<<?fun_end:8>>|[Script|Tail]]],NewD)
                end;
        _ -> {error, "stack underflow"}
    end;
run2([<<?define:8, Script/binary>>|T], D) ->
    %io:fwrite("run2 define\n"),
    {Definition, Script2, _} = split(?fun_end, Script),
    %true = balanced_r(Definition, 0),
    B = hash:doit(Definition, chalang_constants:hash_size()),
    %replace "recursion" in the definition with a pointer to this.
    DSize = chalang_constants:hash_size(),
    NewDefinition = replace(<<?recurse:8>>, <<2, DSize:32, B/binary>>, Definition),
    %io:fwrite("chalang define function "),
    %compiler_chalang:print_binary(NewDefinition),
    %io:fwrite("\n"),
    M = maps:put(B, NewDefinition, D#d.funs),
    S = size(NewDefinition) + size(B),
    MF = D#d.many_funs + 1,
    if
	MF > D#d.fun_limit ->
	    {error, "too many functions"};
	true ->
	    NewD = D#d{op_gas = D#d.op_gas - S - 30,
		       ram_current = D#d.ram_current + (2 * S),
		       many_funs = MF,
		       funs = M},
	    run2([Script2|T], NewD)
    end;
run2([<<?return:8, _/binary>>|_], D) ->
    run2([<<>>], D);
run2([<<Command:8, Script/binary>>|T], D) 
  when ((Command == ?bool_and) or 
        (Command == ?bool_or) or 
        (Command == ?bool_xor)) ->
    io:fwrite("run2 bool and/or/xor\n"),
    case D#d.stack of
        [<<A:32>>|[<<B:32>>|R]] ->
            io:fwrite("bool combine\n"),
            C = bool2(Command, A, B),
            D2 = D#d{stack = [<<C:32>>|R],
                     op_gas = D#d.op_gas - 1,
                     ram_current = D#d.ram_current - 2},
            run2([Script|T], D2);
        [_|[_|_]] -> 
            io:fwrite("can only bool_and two 4 byte values\n"),
            {error, "can only bool_and two 4 byte values"};
        _ -> 
            io:fwrite("stack undeflow\n"),
            {error, "stack underflow"}
    end;
    
run2([<<Command:8, Script/binary>>|T], D) ->
    case run4(Command, D) of
	{error, R} -> {error, R};
	NewD -> 
	    %io:fwrite("run word "),
	    %io:fwrite(integer_to_list(Command)),
	    %io:fwrite("\n"),
	    run2([Script|T], NewD)
    end.
bool2(?bool_and, _, 0) -> 0;
bool2(?bool_and, 0, _) -> 0;
bool2(?bool_and, _, _) -> 1;
bool2(?bool_or, 0, 0) -> 0;
bool2(?bool_or, _, _) -> 1;
bool2(?bool_xor, 0, 0) -> 0;
bool2(?bool_xor, 0, _) -> 1;
bool2(?bool_xor, _, 0) -> 1;
bool2(?bool_xor, _, _) -> 0.
    

run4(?print, D) ->
    print_stack(D#d.stack),
    D;
run4(?drop, D) ->
    case D#d.stack of 
	[H|T] ->
	    D#d{stack = T,
		ram_current = D#d.ram_current - memory(H) - 2,%drop leaves, and the list link is gone
		op_gas = D#d.op_gas - 1};
	_ -> {error, "stack underflow"}
    end;
run4(?dup, D) ->
    case D#d.stack of
        [H|T] ->
            D#d{stack = [H|[H|T]],
                ram_current = D#d.ram_current + memory(H),
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?swap, D) ->
    case D#d.stack of
        [A|[B|C]] ->
            Stack2 = [B|[A|C]],
            D#d{stack = Stack2,
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?tuck, D) ->
    case D#d.stack of
        [A|[B|[C|E]]] ->
            Stack2 = [B|[C|[A|E]]],
            D#d{stack = Stack2,
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?rot, D) ->
    case D#d.stack of
        [A|[B|[C|E]]] ->
            Stack2 = [C|[A|[B|E]]],
            D#d{stack = Stack2,
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?ddup, D) ->
    case D#d.stack of 
        [A|[B|C]] ->
            Stack2 = [A|[B|[A|[B|C]]]],
            D#d{stack = Stack2,
                ram_current = D#d.ram_current +
                memory(A) + memory(B),
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?tuckn, D) ->
    case D#d.stack of
        [N|[X|S]] ->
            H = lists:sublist(S, 1, N),
            T = lists:sublist(S, N+1, 100000000000000000),
            Stack2 = H ++ [X|T],
            D#d{stack = Stack2,
                op_gas = D#d.op_gas - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?pickn, D) ->
    case D#d.stack of
        [N|S] ->
            H = lists:sublist(S, 1, N - 1),
            case lists:sublist(S, N, 100000000000000000) of
                [X|T] ->
                    Stack2 = [X|(H ++ T)],
                    D#d{stack = Stack2,
                        op_gas = D#d.op_gas - 1};
                _ -> {error, "stack underflow"}
            end;
        _ -> {error, "stack underflow"}
    end;
run4(?to_r, D) ->
    case D#d.stack of
        [H|T] ->
            D#d{stack = T,
                op_gas = D#d.op_gas - 1,
                alt = [H|D#d.alt]};
        _ -> {error, "stack underflow"}
    end;
run4(?from_r, D) ->
    case D#d.alt of
        [H|T] ->
            D#d{stack = [H|D#d.stack],
                alt = T,
                op_gas = D#d.op_gas - 1};
        _ -> {error, "alt stack underflow"}
    end;
run4(?r_fetch, D) ->
    case D#d.alt of
        [H|T] ->
            D#d{stack = [H|D#d.stack],
                op_gas = D#d.op_gas - 1};
        _ -> {error, "alt stack underflow"}
    end;
run4(?hash, D) ->
    case D#d.stack of
        [H|T] ->
            D#d{stack = [hash:doit(H, D#d.hash_size)|T],
                op_gas = D#d.op_gas - 20};
        _ -> {error, "stack underflow"}
    end;
run4(?verify_sig, D) ->
    case D#d.stack of
        [Pub|[Data|[Sig|T]]] ->
            B = sign:verify_sig(Data, Sig, Pub),
            B2 = case B of
                     true -> <<1:(?int_bits)>>;
                     false -> <<0:(?int_bits)>>
                                  end,
            D#d{stack = [B2|T],
                op_gas = D#d.op_gas - 20};
        _ -> {error, "stack underflow"}
    end;
run4(X, D) when (X >= ?add) and (X < ?eq) ->
    case D#d.stack of
        [A|[B|C]] ->
            D#d{stack = [arithmetic_chalang:doit(X, A, B)|C],
                op_gas = D#d.op_gas - 1,
                ram_current = D#d.ram_current - 2};
        _ -> {error, "stack underflow"}
    end;
run4(?eq, D) ->
    case D#d.stack of
        [A|[B|_]] ->
            C = if
                    A == B -> 1;
                    true -> 0
                end,
            S = [<<C:?int_bits>>|D#d.stack],
            D#d{stack = S, 
                op_gas = D#d.op_gas - 1,
                ram_current = D#d.ram_current + 1};
        _ -> {error, "stack underflow"}
    end;
run4(?bool_flip, D) ->
    D2 = D#d{op_gas = D#d.op_gas - 1},
    case D#d.stack of
        [<<0:32>>|T] -> D2#d{stack = [<<1:32>>|T]};
        [<<_:32>>|T] -> D2#d{stack = [<<0:32>>|T]};
        [X|T] -> {error, "can only bool flip a 4 byte value"};
        _ -> {error, "stack underflow"}
    end;
run4(?bin_and, D) ->
    case D#d.stack of
        [G|[H|T]] ->
            B = 8 * size(G),
            D = 8 * size(H),
            <<A:B>> = G,
            <<C:D>> = H,
            E = max(B, D),
            F = A band C,
            D#d{op_gas = D#d.op_gas - E,
                stack = [<<F:E>>|T],
                ram_current = D#d.ram_current - min(B, D) - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?bin_or, D) ->
    case D#d.stack of
        [G|[H|T]] ->
            B = 8 * size(G),
            D = 8 * size(H),
            <<A:B>> = G,
            <<C:D>> = H,
            E = max(B, D),
            F = A bor C,
            D#d{op_gas = D#d.op_gas - E,
                stack = [<<F:E>>|T],
                ram_current = D#d.ram_current - min(B, D) - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?bin_xor, Data) ->
    case Data#d.stack of
    [G|[H|T]] ->
            B = 8 * size(G),
            D = 8 * size(H),
            <<A:B>> = G,
            <<C:D>> = H,
            E = max(B, D),
            F = A bxor C,
            Data#d{op_gas = Data#d.op_gas - E,
                   stack = [<<F:E>>|T],
                   ram_current = Data#d.ram_current - min(B, D) - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?stack_size, D) ->
    S = D#d.stack,
    D#d{op_gas = D#d.op_gas - 1,
	ram_current = D#d.ram_current + 2,
	stack = [<<(length(S)):?int_bits>>|S]};
run4(?height, D) ->
    S = D#d.stack,
    H = D#d.state#state.height,
    D#d{op_gas = D#d.op_gas - 1,
	ram_current = D#d.ram_current + 2,
	stack = [<<H:?int_bits>>|S]};
run4(?gas, D) ->
    G = D#d.op_gas,
    D#d{op_gas = G - 1,
	stack = [<<G:?int_bits>>|D#d.stack],
	ram_current = D#d.ram_current + 2};
run4(?many_vars, D) ->
    D#d{op_gas = D#d.op_gas - 1,
	stack = [<<(size(D#d.vars)):?int_bits>>|D#d.stack],
	ram_current = D#d.ram_current + 2};
run4(?many_funs, D) ->
    D#d{op_gas = D#d.op_gas - 1,
	stack = [<<(D#d.many_funs):?int_bits>>|D#d.stack],
	ram_current = D#d.ram_current + 2};
run4(?fun_end, D) ->
    D#d{op_gas = D#d.op_gas - 1};
run4(?set, D) ->
    case D#d.stack of
        [<<Key:32>>|[Value|T]] ->
            if 
                (Key > size(D#d.vars)) ->
                    {error, "ran out of space for variables"};
                true ->
                    Vars = setelement(Key, D#d.vars, Value),
                    D#d{op_gas = D#d.op_gas - 1,
                        stack = T,
                        vars = Vars}
            end;
        _ -> {error, "stack underflow"}
    end;
run4(?fetch, D) ->
    case D#d.stack of
        [<<Key:32>>|T] ->
            if
                (Key > size(D#d.vars)) ->
                    {error, "cannot fetch variables from outside the allocated space"};
                true ->
                    Value = case element(Key, D#d.vars) of
                                e -> [];
                                V -> V
                            end,
                    D#d{op_gas = D#d.op_gas - 1,
                        stack = [Value|T],
                        ram_current = D#d.ram_current + memory(Value) + 1}
            end;
        _ -> {error, "stack underflow"}
    end;
run4(?cons, D) -> % ( A [B] -- [A, B] )
    case D#d.stack of
        [A|[B|T]] ->
            D#d{op_gas = D#d.op_gas - 1,
                stack = [[B|A]|T],
                ram_current = D#d.ram_current + 1};
        _ -> {error, "stack underflow"}
    end;
run4(?car, D) -> % ( [A, B] -- A [B] )
    case D#d.stack of
        [[B|A]|T] ->
            D#d{op_gas = D#d.op_gas - 1,
                stack = [A|[B|T]],
                ram_current = D#d.ram_current - 1};
        _ -> {error, "stack undeflow"}
    end;
run4(?nil, D) ->
    D#d{op_gas = D#d.op_gas - 1,
	stack = [[]|D#d.stack],
	ram_current = D#d.ram_current + 1};
run4(?append, D) ->
    case D#d.stack of
        [A|[B|T]] ->
            C = if
                    is_binary(A) and is_binary(B) ->
                        <<B/binary, A/binary>>;
                    is_list(A) and is_list(B) ->
                        B ++ A
                end,
            D#d{op_gas = D#d.op_gas - 1,
                stack = [C|T],
                ram_current = D#d.ram_current + 1};
        _ -> {error, "stack underflow"}
    end;
run4(?split, D) ->
    case D#d.stack of
        [<<N:?int_bits>>|[L|T]] ->
            M = N * 8,
            if
                is_binary(L) ->
                    <<A:M, B/binary>> = L,
                    D#d{op_gas = D#d.op_gas - 1,
                        stack = [<<A:M>>|[B|T]],
                        ram_current = D#d.ram_current - 1};
                true -> {error, "can only split binaries"}
            end;
        [_|[_|_]] -> {error, "need to use a 4-byte integer to say where to split the binary"};
        _ -> {error, "stack underflow"}
    end;
run4(?reverse, D) ->
    case D#d.stack of
        [H|T] ->
            if
                is_list(H) ->
                    D#d{op_gas = D#d.op_gas - length(H),
                        stack = [lists:reverse(H)|T]};
                true -> {error, "can only reverse a list"}
            end;
        _ -> {error, "stack underflow"}
    end;
run4(?is_list, D) ->
    case D#d.stack of
        [H|T] ->
            G = if
                    is_list(H) -> <<1:?int_bits>>;
                    true -> (<<0:?int_bits>>)
                end,
            D#d{op_gas = D#d.op_gas - 1,
                stack = [G|[H|T]],
                ram_current = D#d.ram_current - 1};
        _ -> {error, "stack underflow"}
    end;
run4(?nop, D) -> D;
run4(?fail, D) -> 
    {error, "fail"}.

memory(L) -> memory(L, 0).
memory([], X) -> X+1;
memory([H|T], X) -> memory(T, 1+memory(H, X));
memory(B, X) -> X+size(B).
balanced_f(<<>>, 0) -> true;
balanced_f(<<>>, 1) -> false;
balanced_f(<<?define:8, Script/binary>>, 0) ->
    balanced_f(Script, 1);
balanced_f(<<?define:8, _/binary>>, 1) -> false;
balanced_f(<<?fun_end:8, Script/binary>>, 1) ->
    balanced_f(Script, 0);
balanced_f(<<?fun_end:8, _/binary>>, 0) -> false;
balanced_f(<<?int:8, _:?int_bits, Script/binary>>, X) ->
    balanced_f(Script, X);
balanced_f(<<?binary:8, H:32, Script/binary>>, D) ->
    X = H * 8,
    <<_:X, Script2/binary>> = Script,
    balanced_f(Script2, D);
balanced_f(<<_:8, Script/binary>>, X) ->
    balanced_f(Script, X).
none_of(X) -> none_of(X, ?return).
none_of(<<>>, _) -> true;
none_of(<<X:8, _/binary>>, X) -> false;
none_of(<<?int:8, _:?int_bits, Script/binary>>, X) -> 
    none_of(Script, X);
none_of(<<?binary:8, H:32, Script/binary>>, D) -> 
    X = H * 8,
    <<_:X, Script2/binary>> = Script,
    none_of(Script2, D);
none_of(<<_:8, Script/binary>>, X) -> 
    none_of(Script, X).
replace(Old, New, Binary) ->
    replace(Old, New, Binary, 0).
replace(_, _, B, P) when (P div 8) > size(B) ->
    B;
replace(Old, New, Binary, Pointer) ->
    %io:fwrite("replace\n"),
    N = 8 * size(Old),
    <<AB:N>> = Old,
    case Binary of
	<<D:Pointer, AB:N, R/binary>> ->
	    R2 = replace(Old, New, R),
	    <<D:Pointer, New/binary, R2/binary>>;
	<<_:Pointer, ?int:8, _:?int_bits, _/binary>> ->
	    replace(Old, New, Binary, Pointer+8+?int_bits);
	<<_:Pointer, ?binary:8, H:32, _/binary>> ->
	    X = H * 8,
	    replace(Old, New, Binary, Pointer+8+32+X);
	_ -> replace(Old, New, Binary, Pointer+8)
    end.
	    
split(X, B) ->
    split(X, B, 0).
split(X, B, N) ->
    <<_:N, Y:8, _C/binary>> = B,
    case Y of
	?int -> split(X, B, N+8+?int_bits);
	?binary ->
	    <<_:N, Y:8, H:32, _/binary>> = B,
	    %J = H*8,
	    %<<_:N, Y:8, H:8, _:H, _/binary>> = B,
	    %split(X, B, N+16+(H*8));
	    split(X, B, N+40+(H*8));
	X ->
	    <<A:N, Y:8, T/binary>> = B,
	    {<<A:N>>, T, N};
	_ -> split(X, B, N+8)
    end.
split_if(X, B) ->
    split_if(X, B, 0).
split_if(X, B, N) ->
    <<_:N, Y:8, C/binary>> = B,
    case Y of
	?int -> split_if(X, B, N+8+?int_bits);
	?binary ->
	    <<_:N, Y:8, H:32, _/binary>> = B,
	    %J = H*8,
	    %<<_:N, Y:8, H:8, _:H, _/binary>> = B,
	    split_if(X, B, N+40+(H*8));
	?caseif ->
	    {_, _Rest, M} = split_if(?then, C),
	    split_if(X, B, N+M+16);
	X ->
	    <<A:N, Y:8, T/binary>> = B,
	    {<<A:N>>, T, N};
	_ -> split_if(X, B, N+8)
    end.
%split_list(N, L) ->
%    split_list(N, L, []).
%split_list(0, A, B) ->
%    {lists:reverse(B), A};
%split_list(N, [H|T], B) ->
%    split_list(N-1, T, [H|B]).
print_stack(X) ->
    print_stack(12, X),
    io:fwrite("\n").
print_stack(_, []) -> io:fwrite("[]");
print_stack(0, _) -> io:fwrite("\n");
print_stack(N, [H]) ->
    io:fwrite("["),
    print_stack(N-1, H),
    io:fwrite("]");
print_stack(N, [H|T]) ->
    io:fwrite("["),
    print_stack(N-1, H),
    io:fwrite("|"),
    print_stack(N - 1, T),
    io:fwrite("]");
print_stack(_, <<X:8>>) ->
    io:fwrite("c"++integer_to_list(X) ++" ");
print_stack(_, <<N:32>>) ->
    io:fwrite("i"++integer_to_list(N) ++" ");
%print_stack(_, <<F:32, G:32>>) ->
%    io:fwrite(" " ++integer_to_list(F) ++"/"++
		  %integer_to_list(G) ++" ");
print_stack(_, B) -> io:fwrite(binary_to_list(base64:encode(B)) ++ "\n").
