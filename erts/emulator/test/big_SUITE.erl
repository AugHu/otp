%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1997-2011. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(big_SUITE).


-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2]).
-export([t_div/1, eq_28/1, eq_32/1, eq_big/1, eq_math/1, big_literals/1,
	 borders/1, negative/1, big_float_1/1, big_float_2/1,
	 shift_limit_1/1, powmod/1, system_limit/1, toobig/1, otp_6692/1]).

%% Internal exports.
-export([eval/1]).
-export([init/3]).

-export([fac/1, fib/1, pow/2, gcd/2, lcm/2]).

-export([init_per_testcase/2, end_per_testcase/2]).

-include_lib("test_server/include/test_server.hrl").

suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    [t_div, eq_28, eq_32, eq_big, eq_math, big_literals,
     borders, negative, {group, big_float}, shift_limit_1,
     powmod, system_limit, toobig, otp_6692].

groups() -> 
    [{big_float, [], [big_float_1, big_float_2]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


init_per_testcase(Func, Config) when is_atom(Func), is_list(Config) ->
    Dog=?t:timetrap(?t:minutes(3)),
    [{watchdog, Dog}|Config].

end_per_testcase(_Func, Config) ->
    Dog=?config(watchdog, Config),
    ?t:timetrap_cancel(Dog).

%%
%% Syntax of data files:
%% Expr1 = Expr2.
%% ...
%% built in functions are:
%% fac(N).
%% fib(N).
%% pow(X, N)  == X ^ N
%% gcd(Q, R) 
%% lcm(Q, R)
%%
eq_28(Config) when is_list(Config) ->
    TestFile = test_file(Config, "eq_28.dat"),
    test(TestFile).

eq_32(Config) when is_list(Config) ->
    TestFile = test_file(Config, "eq_32.dat"),
    test(TestFile).

eq_big(Config) when is_list(Config) ->
    TestFile = test_file(Config, "eq_big.dat"),
    test(TestFile).

eq_math(Config) when is_list(Config) ->
    TestFile = test_file(Config, "eq_math.dat"),
    test(TestFile).


borders(doc) -> "Tests border cases between small/big.";
borders(Config) when is_list(Config) ->
    TestFile = test_file(Config, "borders.dat"),
    test(TestFile).

negative(Config) when is_list(Config) ->
    TestFile = test_file(Config, "negative.dat"),
    test(TestFile).
    

%% Find test file
test_file(Config, Name) ->
    DataDir = ?config(data_dir, Config),
    filename:join(DataDir, Name).

%%
%%
%% Run test on file test_big_seq.erl
%%
%%
test(File) ->
    test(File, [node()]).

test(File, Nodes) ->
    ?line {ok,Fd} = file:open(File, [read]),
    Res = test(File, Fd, Nodes),
    file:close(Fd),
    case Res of
	{0,Cases} -> {comment, integer_to_list(Cases) ++ " cases"};
	{_,_} -> test_server:fail()
    end.

test(File, Fd, Ns) ->
    test(File, Fd, Ns, 0, 0, 0).

test(File, Fd, Ns, L, Cases, Err) ->
    case io:parse_erl_exprs(Fd, '') of
	{eof,_} -> {Err, Cases};
	{error, {Line,_Mod,Message}, _} ->
	    Fmt = erl_parse:format_error(Message),
	    io:format("~s:~w: error ~s~n", [File, Line+L, Fmt]),
	    {Err+1, Cases};
	{ok, [{match,ThisLine,Expr1,Expr2}], Line} ->
	    case multi_match(Ns, {op,0,'-',Expr1,Expr2}) of
		[] ->
		    test(File, Fd, Ns, Line+L-1,Cases+1, Err);
		[_|_] ->
		    PP = erl_pp:expr({op,0,'=/=',Expr1,Expr2}),
		    io:format("~s:~w : error ~s~n", [File,ThisLine+L, PP]),
		    test(File, Fd, Ns, Line+L-1,Cases+1, Err+1)
	    end;
	{ok, Exprs, Line} ->
	    PP = erl_pp:exprs(Exprs),
	    io:format("~s: ~w: equation expected not ~s~n", [File,Line+L,PP]),
	    test(File, Fd, Ns, Line+L-1,Cases+1, Err+1)
    end.

multi_match(Ns, Expr) ->
    multi_match(Ns, Expr, []).

multi_match([Node|Ns], Expr, Rs) ->
    ?line X = rpc:call(Node, big_SUITE, eval, [Expr]),
    if X == 0 -> multi_match(Ns, Expr, Rs);
       true -> multi_match(Ns, Expr, [{Node,X}|Rs])
    end;
multi_match([], _, Rs) -> Rs.

eval(Expr) ->
    LFH = fun(Name, As) -> apply(?MODULE, Name, As) end,

    %% Applied arithmetic BIFs.
    {value,V,_} = erl_eval:expr(Expr, [], {value,LFH}),

    %% Real arithmetic instructions.
    V = eval(Expr, LFH),

    V.

%% Like a subset of erl_eval:expr/3, but uses real arithmetic instructions instead of
%% applying them (it does make a difference).

eval({op,_,Op,A0}, LFH) ->
    A = eval(A0, LFH),
    Res = eval_op(Op, A),
    erlang:garbage_collect(),
    Res;
eval({op,_,Op,A0,B0}, LFH) ->
    [A,B] = eval_list([A0,B0], LFH),
    Res = eval_op(Op, A, B),
    erlang:garbage_collect(),
    Res;
eval({integer,_,I}, _) -> I;
eval({call,_,{atom,_,Local},Args0}, LFH) ->
    Args = eval_list(Args0, LFH),
    LFH(Local, Args).

eval_list([E|Es], LFH) ->
    [eval(E, LFH)|eval_list(Es, LFH)];
eval_list([], _) -> [].

eval_op('-', A) -> -A;
eval_op('+', A) -> +A;
eval_op('bnot', A) -> bnot A.

eval_op('-', A, B) -> A - B;
eval_op('+', A, B) -> A + B;
eval_op('*', A, B) -> A * B;
eval_op('div', A, B) -> A div B;
eval_op('rem', A, B) -> A rem B;
eval_op('band', A, B) -> A band B;
eval_op('bor', A, B) -> A bor B;
eval_op('bxor', A, B) -> A bxor B;
eval_op('bsl', A, B) -> A bsl B;
eval_op('bsr', A, B) -> A bsr B.

%% Built in test functions

fac(0) -> 1;
fac(1) -> 1;
fac(N) -> N * fac(N-1).

%%
%% X ^ N
%%
pow(_, 0) -> 1;
pow(X, 1) -> X;
pow(X, N) when (N band 1) == 1 ->
    X2 = pow(X, N bsr 1),
    X*X2*X2;
pow(X, N) ->
    X2 = pow(X, N bsr 1),
    X2*X2.

fib(0) -> 1;
fib(1) -> 1;
fib(N) -> fib(N-1) + fib(N-2).

%%
%% Gcd 
%%
gcd(Q, 0) -> Q;
gcd(Q, R) -> gcd(R, Q rem R).

%%
%% Least common multiple
%%
lcm(Q, R) ->
    Q*R div gcd(Q, R).


%% Test case t_div cut in from R2D test suite.

t_div(Config) when is_list(Config) ->
    ?line 'try'(fun() -> 98765432101234 div 98765432101235 end, 0),

    % Big remainder, small quotient.
    ?line 'try'(fun() -> 339254531512 div 68719476736 end, 4),
    ok.

'try'(Fun, Result) ->
    'try'(89, Fun, Result, []).

'try'(0, _, _, _) ->
    ok;
'try'(Iter, Fun, Result, Filler) ->
    spawn(?MODULE, init, [self(), Fun, list_to_tuple(Filler)]),
    receive
	{result, Result} ->
	    'try'(Iter-1, Fun, Result, [0|Filler]);
	{result, Other} ->
	    io:format("Expected ~p; got ~p~n", [Result, Other]),
	    test_server:fail()
    end.

init(ReplyTo, Fun, _Filler) ->
    ReplyTo ! {result, Fun()}.

big_literals(doc) ->
    "Tests that big-number literals work correctly.";
big_literals(Config) when is_list(Config) ->
    %% Note: The literal test cannot be compiler on a pre-R4 Beam emulator,
    %% so we compile it now.
    ?line DataDir = ?config(data_dir, Config),
    ?line Test = filename:join(DataDir, "literal_test"),
    ?line {ok, Mod, Bin} = compile:file(Test, [binary]),
    ?line {module, Mod} = code:load_binary(Mod, Mod, Bin),
    ?line ok = Mod:t(),
    ok.


big_float_1(doc) ->
    ["OTP-2436, part 1"];
big_float_1(Config) when is_list(Config) ->
    %% F is a number very close to a maximum float.
    ?line F = id(1.7e308),
    ?line I = trunc(F),
    ?line true = (I == F),
    ?line false = (I /= F),
    ?line true = (I > F/2),
    ?line false = (I =< F/2),
    ?line true = (I*2 >= F),
    ?line false = (I*2 < F),
    ?line true = (I*I > F),
    ?line false = (I*I =< F),

    ?line true = (F == I),
    ?line false = (F /= I),
    ?line false = (F/2 > I),
    ?line true = (F/2 =< I),
    ?line false = (F >= I*2),
    ?line true = (F < I*2),
    ?line false = (F > I*I),
    ?line true = (F =< I*I),
    ok.

big_float_2(doc) ->
    ["OTP-2436, part 2"];
big_float_2(Config) when is_list(Config) ->
    ?line F = id(1.7e308),
    ?line I = trunc(F),
    ?line {'EXIT', _} = (catch 1/(2*I)),
    ?line _Ignore = 2/I,
    ?line {'EXIT', _} = (catch 4/(2*I)),
    ok.

shift_limit_1(doc) ->
    ["OTP-3256"];
shift_limit_1(Config) when is_list(Config) ->
    ?line case catch (id(1) bsl 100000000) of
	      {'EXIT', {system_limit, _}} ->
		  ok
	  end,
    ok.

powmod(Config) when is_list(Config) ->
    A = 1696192905348584855517250509684275447603964214606878827319923580493120589769459602596313014087329389174229999430092223701630077631205171572331191216670754029016160388576759960413039261647653627052707047,
    B = 43581177444506616087519351724629421082877485633442736512567383077022781906420535744195118099822189576169114064491200598595995538299156626345938812352676950427869649947439032133573270227067833308153431095,
    C = 52751775381034251994634567029696659541685100826881826508158083211003576763074162948462801435204697796532659535818017760528684167216110865807581759669824808936751316879636014972704885388116861127856231,
    42092892863788727404752752803608028634538446791189806757622214958680350350975318060071308251566643822307995215323107194784213893808887471095918905937046217646432382915847269148913963434734284563536888 = powmod(A, B, C),
    ok.

powmod(A, 1, C) ->
    A rem C;
powmod(A, 2, C) ->
    A*A rem C;
powmod(A, B, C) ->
    B1 = B div 2,
    B2 = B - B1,
    P = powmod(A, B1, C),
    case B2 of
	B1 ->
	    (P*P) rem C;
	_  -> 
	    (P*P*A) rem C
    end.

system_limit(Config) when is_list(Config) ->
    ?line Maxbig = maxbig(),
    ?line {'EXIT',{system_limit,_}} = (catch Maxbig+1),
    ?line {'EXIT',{system_limit,_}} = (catch -Maxbig-1),
    ?line {'EXIT',{system_limit,_}} = (catch 2*Maxbig),
    ?line {'EXIT',{system_limit,_}} = (catch bnot Maxbig),
    ?line {'EXIT',{system_limit,_}} = (catch apply(erlang, id('bnot'), [Maxbig])),
    ?line {'EXIT',{system_limit,_}} = (catch Maxbig bsl 2),
    ?line {'EXIT',{system_limit,_}} = (catch apply(erlang, id('bsl'), [Maxbig,2])),
    ?line {'EXIT',{system_limit,_}} = (catch id(1) bsl (1 bsl 45)),
    ?line {'EXIT',{system_limit,_}} = (catch id(1) bsl (1 bsl 69)),
    ok.

maxbig() ->
    %% We assume that the maximum arity is (1 bsl 19) - 1.
    Ws = erlang:system_info(wordsize),
    (((1 bsl ((16777184 * (Ws div 4))-1)) - 1) bsl 1) + 1.

id(I) -> I.

toobig(Config) when is_list(Config) ->
    ?line {'EXIT',{{badmatch,_},_}} = (catch toobig()),
    ok.

toobig() ->
    A = erlang:term_to_binary(lists:seq(1000000, 2200000)),
    ASize = erlang:bit_size(A),
    <<ANr:ASize>> = A, % should fail
    ANr band ANr.

otp_6692(suite) ->
    [];
otp_6692(doc) ->
    ["Tests for DIV/REM bug reported in OTP-6692"];
otp_6692(Config) when is_list(Config)->
    ?line loop1(1,1000).

fact(N) ->
     fact(N,1).

fact(0,P) -> P;
fact(N,P) -> fact(N-1,P*N).

raised(X,1) ->
    X;
raised(X,N) ->
    X*raised(X,N-1).

loop1(M,M) ->
    ok;
loop1(N,M) ->
    loop2(fact(N),raised(7,7),1,8),
    loop1(N+1,M).

loop2(_,_,M,M) ->
    ok;
loop2(X,Y,N,M) ->
    Z = raised(Y,N),
    case X rem Z of
	Z ->
	    exit({failed,X,'REM',Z,'=',Z});
	0 ->
	    case (X div Z) * Z of
		X ->
		    ok;
		Wrong ->
		    exit({failed,X,'DIV',Z,'*',Z,'=',Wrong})
	    end;
	_ ->
	    ok
    end,
    loop2(X,Y,N+1,M).
    
