---
layout: post
title: "Canonical Structures: Implicits for the masses"
date: 2026-06-26
---

Original source: [Original post](<https://okmij.org/ftp/ML/canonical.html>)

Canonical Structures: Implicits for the masses

[previous](https://okmij.org/ftp/Computation/typeclass.html)   [next](https://okmij.org/ftp/Computation/types.html#sessions)   [start](https://okmij.org/ftp/ML/index.html)   [top](https://okmij.org/ftp/)

# Canonical Structures: Programmable type classes and implicits

 

Canonical Structures are a facility to obtain a value
of a given type -- for example, a value of the type `int->string`:
the function to ``show'' an integer. Since there are many such
functions, the user has to register the ``canonical'' value of this
type. In the simplest case, obtaining the canonical value is a
mere look up in the database of registered values. Instead of a
canonical value itself, however, the database may provide a rule how
to make it, from some other registered values: e.g., how to ``show'' a
pair if we can show its components. Querying this database of facts
and rules is quite like the evaluation of a logic-programming query.

From the point of view of the Curry-Howard correspondence, finding a
term of a given type is finding a proof of a proposition. This is how
this facility was first developed in Coq, as a programmable type inference
for proof search. It is actually a general and flexible
technique of overloading resolution, and deserves to be known and used
in programming at large.

- [Introduction](https://okmij.org/ftp/ML/canonical.html#intro)

- [Canonical structures in Coq](https://okmij.org/ftp/ML/canonical.html#canon)

- [Canonical structures in OCaml: Gentle introduction](https://okmij.org/ftp/ML/canonical.html#gentle)

- [A library for canonical structures](https://okmij.org/ftp/ML/canonical.html#full)

- [Canonical structures in meta-programming](https://okmij.org/ftp/ML/canonical.html#meta)

-  

- [Type Representations](https://okmij.org/ftp/ML/canonical.html#trep)

 

## Introduction

Overloading -- using the same name in several, perhaps related
meanings -- is common in natural and programming languages: for
example, `equal' and the `=` sign. Our experience, and experiments, agree that
precision may hinder (human) comprehension, by burying the important in
details. Certain degree of ambiguity appears necessary.

However useful overloading may be for concise communication,
eventually the receiving party has to determine what exactly a given
ambiguous word refers to -- that is, to resolve the
overloading. The context is the key, literally. One can think
of overloading resolution as an `intelligent' search in a database
of possible referents, indexed by some representation of
the context, often a type. To put it another way, overloading resolution
is, conceptually, evaluating a logic-programming query. This view
unifies various forms of overloading in programming: ad hoc overloading (C++,
CLOS, and many others), type classes (Haskell), implicits (Scala and
now others). 

This page is about Canonical Structures, first appeared in Coq as a
programmable unification. In this form of overloading, the resolution
is not just conceptually running a Prolog-like query: it is literally
so. Furthermore, the logic program -- the database of facts and
rules -- is user-programmable. And so are the details of the
resolution algorithm: One may allow `overlapping instances' -- or
prohibit them, insisting on uniquely resolvable overloading. One
may make the search fully deterministic, fully non-deterministic, or
something in-between.

This article and the accompanying code are to explain and implement canonical
structures in plain OCaml and encourage experimentation. The title
could have been `Canonical Structures for the working OCaml
(meta) programmer'. The rudiment of canonical structures is already
present in OCaml, in the form of the registry of printers for
user-defined types: `#install_printer`. It is available only at the
top-level, however, and deeply intertwined with it. As a modest
practical benefit, this facility is now available for all programs, as
a plain, small, self-contained library, with no compiler or other
magic. We have used this library in a realistic project: an embedded
session-typed DSL for service-oriented programming. 

Although canonical structures have already proved useful in OCaml as
it is, they would become more convenient when run-time types get
compiler support. Canonical structures are also useful in MetaOCaml:
they are by nature a meta-programming facility.

#### Version

The current version is September 2019

#### References

Thomas Wasow, Amy Perfors an David Beaver: The Puzzle of
Ambiguity

<[http://www.stanford.edu/~wasow/Lapointe.pdf](http://www.stanford.edu/~wasow/Lapointe.pdf)>

[Programming as collaborative reference](https://okmij.org/ftp/Computation/index.html#collaborative-PL)

`Implicits for the masses'

The first version of this article, posted on the
caml-list on Sep 5, 2019

 

## Canonical structures in Coq

> 

``One of the key ingredients to the concision, and intelligibility, of
a mathematical text is the use of notational conventions and even
sometimes the abuse thereof. These notational conventions are
usually shaped by decades of practice by the specialists of a given
mathematical community.... A trained reader can hence easily infer
from the context of a typeset mathematical formula he is reading all
the information that is not explicit in the formula but that is
nonetheless necessary to the precise description of the mathematical
objects at stake.''

``Formalizing a page of mathematics using a proof assistant requires
the description of objects and proofs at a level of detail that is
few orders of magnitude higher than the one at which a human reader
would understand this description. This paper is about the
techniques that can be used to reproduce at the formal level the
ease authors of mathematics have to omit some part of the
information they would need to provide, because it can be
inferred....''

Thus starts the remarkable paper by Mahboubi and Tassi, which was
the inspiration for the present page. The paper is a gentle tutorial,
which explains how the inferring of omitted details is made part of
type inference, how types come into this, how it is all related to proof search,
and how to program this type inference in a manner reminiscent of
Prolog. (Alas, the paper does not elaborate the latter point and does not
show any Horn clauses.) Albeit gentle, the Mahboubi and Tassi's
tutorial is a Coq tutorial aimed at Coq users. Yet their insights go
beyond Coq and deserve to be known wider.

Inspired by Mahboubi and Tassi's paper, the present page is an attempt
to explain canonical structures for programming rather than theorem
proving, and illustrate them in plain OCaml, elaborating the
connection with logic programming. We show Horn clauses explicitly,
embed them in OCaml and present a very simple and modifiable
Prolog-like interpreter. We changed the running example Mahboubi and
Tassi's, from `Eq` to `Show`.

#### References

Assia Mahboubi, Enrico Tassi:
Canonical Structures for the working Coq user

[doi:10.1007/978-3-642-39634-2_5](http://doi.org/10.1007/978-3-642-39634-2_5)

 

## Canonical structures in OCaml: Gentle introduction

We explain canonical structures by developing their toy implementation
in plain OCaml, in two steps. The implementation here is for a
particular overloading function: `show'. The next section presents a
general and flexible canonical structures library.

We will be implementing the overloaded `show` function, to convert
values of different types to a string: an analogue of Haskell's
`Show` class. To put it another way, given some type `t` we would like
to find a function of the type `t -> string`. Since that type will
appear often, let's introduce an abbreviation for it:

```
 type 'a show_dict = 'a -> string

```

The desired function, call it `find_show`, receives 
a type `t` and finds and returns the corresponding, or `canonical',
value of the type `t show_dict`. Types, however, cannot be passed as
arguments: OCaml is not a dependently-typed
language. What we can pass is a value
representing the type: see the separate article on [Type Representations](https://okmij.org/ftp/ML/canonical.html#trep). Let `t trep` be the type of the value representing the type `t`. 

Thus our goal is to implement the function `find_show : 'a trep -> 'a show_dict`. The generic overloaded `show` is then

```
 let show trep x = (find_show trep) x
 val show: 'a trep -> 'a -> string = <fun>

```

to be used as

```
 let ex1 = show Int 4
 let ex2 = show (Pair (Int,(Pair (Int,Int)))) (10,(11,12))

```

where `Int` of the type `int trep` is the representation of the type
`int`, and `Pair` is the constructor for the representation of pairs.
The type checker can certainly infer the type of `4` and
`(10,(11,12))` and could automatically synthesize the type
representations, `Int` and `Pair (Int,(Pair (Int,Int)))`, resp.,
saving us trouble specifying them explicitly. (Perhaps in near future
OCaml would indeed do such type representation synthesis, as Scala already
does.) What the type checker cannot synthesize is the value of `t show_dict`: after all, there are generally many functions of the type
`t -> string`. The user has to give a hint: which function is to
regard as the *canonical* `t -> string` function.
The job of `find_show` is to follow the hint and find the canonical
function: in effect, find *the*
evidence that the type `t->string` is populated. Keeping Curry-Howard
in mind, `find_show` does a proof search.

The Coq implementation of canonical structures provides the global
registry, a database, in which programmers register the `t show_dict`-like values that are to be considered canonical for the
given type `t`. Here is our first attempt at such registry. The 
following is the type of registry entries: an association of a 
type (via its representative) and the canonical dictionary for it. 

```
 type show_reg_entry = Showable : 'a trep * 'a show_dict -> show_reg_entry (* 'a is existential *)

```

The global database in our toy implementation is a list of entries:

```
 let show_registry : show_reg_entry list ref = ref []

```

The following function is the analogue of the Coq command `Canonical
Structure', to register a canonical value in the database. For
simplicity we skip the check if a type already has a canonical value
registered for it. The check is useful if we insist on the
uniqueness of the resolution and do not allow `overlapping instances'.

```
 let show_register : 'a trep -> 'a show_dict -> unit = fun trep dict ->
 show_registry := Showable (trep,dict) :: !show_registry

```

Finally, `find_show` is the resolution function: it does the simple 
database look-up. Here, `teq : 'a trep -> 'b trep -> ('a,'b) eq option`
is the type equality comparison. If two type representations are
equal, it returns the evidence, in the form of `('a,'b) eq` GADT,
that the types are equal as well.

```
 let find_show : type a. a trep -> a show_dict = fun trep ->
 let rec loop : show_reg_entry list -> a show_dict = function 
 | [] -> failwith "find_show: resolution failed"
 | Showable(trep',dict)::t -> match teq trep trep' with
 | Some Refl -> dict
 | _ -> loop t
 in loop !show_registry

```

After registering the instance of `show` for integers:

```
 let () = show_register Int string_of_int

```

we can run the first example `ex1`.

To review, we have built a database of facts, like the
following:

```
 showable(int,string_of_int).

```

and search it, with the query like `?- showable(int,X).`
This may look familiar to some.

Example `ex2` involves pairs. It is no fun registering canonical
values for each concrete pair type `t1 * t2`. We'd rather
register a rule: how to make the canonical show of a pair if we
already know how to show the two components of the pair. In other
words, we can show pairs *provided* we can show their
components -- which can be written as the Horn clause:

```
 showable(pair(X,Y),R) :- 
 showable(X,DX), showable(Y,DY), R=make_pair_dict(DX,DY).

```

where the function `make_pair_dict` is defined as follows:

```
 let make_pair_dict : 'a show_dict * 'b show_dict -> ('a * 'b) show_dict =
 fun (dx,dy) -> fun (x,y) -> "(" ^ dx x ^ "," ^ dy y ^ ")"

```

All that remains is to represent this Horn clause in OCaml and modify
`find_show` accordingly. The logic variables such as 
`X`, `Y` and `R` above may be a hassle to implement,
however. Fortunately, we can take a shortcut. Our
resolution query always has the form `?- showable(t,R).` where `t` is
a concrete type. That is, we always treat the first argument of the
`showable` relation as the `input' and the second as the `output'. 
Instead of the full unification we, hence, get by with a simpler matching.

In our second attempt, we extend the type of registry
entries to carry not only facts about dictionaries 
but also rules for making them. The representation of
rules looks quite like a first-class pattern.

```
 type show_reg_entry =
 | Fact : 'a trep * 'a show_dict -> show_reg_entry (* as before *)
 | Rule : {pat : 'a. 'a trep -> 'a show_dict option} -> show_reg_entry

```

We add a function to register a rule:

```
 let show_register' : show_reg_entry -> unit = fun entry ->
 show_registry := entry :: !show_registry

```

The new `find_show` does an SLD-like resolution -- but with committed
choice and with fixed modes.

```
 let find_show : type a. a trep -> a show_dict = fun trep ->
 let rec loop : show_reg_entry list -> a show_dict = function 
 | [] -> failwith "find_show: resolution failed"
 | Fact (trep',dict)::t -> begin match teq trep trep' with
 | Some Refl -> dict
 | None -> loop t
 end
 | Rule {pat}::t -> match pat trep with
 | Some dict -> dict
 | None -> loop t
 in loop !show_registry

```

Our resolution clearly does no backtracking: if a rule matches, we
are committed to it and do not look further. In Prolog, our rules
would look as

```
 showable(T,R) :- T = pair(X,Y), !, 
 showable(X,DX), showable(Y,DY), R=make_pair_dict(DX,DY).

```

Canonical Structures in Coq do no backtracking either. 
There is nothing that stops us from supporting
backtracking though: it is left as an experiment for the reader.

We now can register the rule to show pairs, of any showable types:

```
 let () = 
 let pat : type b. b trep -> b show_dict option = function
 | Pair (x,y) -> Some (make_pair_dict (find_show x, find_show y))
 | _ -> None
 in 
 show_register' @@ Rule {pat}

```

and run both examples `ex1` and `ex2`.

Next we present a `production-ready' version of the library, which
works beyond `show' and is also easier to experiment with.

#### References

[canonical_leadup.ml](https://okmij.org/ftp/ML/canonical_leadup.ml) [8K]

The complete code for the tutorial

[Type Representations](https://okmij.org/ftp/ML/canonical.html#trep)

[Type-class resolution via intensional type analysis:](https://okmij.org/ftp/Computation/typeclass.html#intensional)
many parallels to canonical structures

 

## A library for canonical structures

We now present the full library of canonical structures in OCaml,
supporting arbitrary overloaded functions on arbitrary, including
user-defined types. Overloading is resolved using facts (which
concrete function to use for a particular concrete type) as well as
rules, e.g., to handle all pairs or all list types generically. We
demonstrate the library on a series of examples, from the familiar show
to read to read-show, including the composition of read and show. We
also illustrate `overlapping instances': pairs of booleans are to be
shown in a particular way rather than generically.

The first example is to show values of different types, and the types
themselves. This is the extension of the running example of the
previous section. We define the two overloaded functions:

```
 module ShowType = MakeResolve(struct type 'a dict = string end)
 module Show = MakeResolve(struct type 'a dict = 'a -> string end)

```

and their simple instances: `facts' of overloading:

```
 let () = ShowType.register Int "Int"
 let () = ShowType.register Bool "Bool"
 
 let () = Show.register Int string_of_int
 let () = Show.register Bool string_of_bool

```

We can now show integers:

```
 Show.find Int 1

```

Since our Canonical Structures are implemented completely outside the
compiler, the types of
values to look up have to be explicitly specified as values of the 
`'a trep` data type, which represents types at the value level. For
example, the value `Int` represents the type `int` (and
itself has the type `int trep`). The data type can be easily
extended with representations of user-defined data types (we show
an example later). The `trep` values may be
regarded as type annotations; in particular, as with other type
annotations, if the user sets them wrong, the type error is
imminent. Therefore, they are not an additional source of mistakes,
but still cumbersome. If a compiler could somehow ``reflect'' an
inferred type of an expression and synthesize a `trep` value, these
annotations could be eliminated. 

To show pairs, we register the generic rule

```
 let () = 
 let open Show in
 let pat : type b. b trep -> b dict option = function
 | Pair (tx,ty) -> Some (fun (x,y) -> "(" ^ find tx x ^ "," ^ find ty y ^ ")")
 | _ -> None
 in 
 register_rule {pat}

```

(The rule for `ShowType` is elided.)
Our library permits `overlapping instances'. To illustrate, we
register a particular show for pairs of booleans.

```
 let () = Show.register (Pair(Bool,Bool)) @@
 let btos = function true -> "T" | false -> "F" in
 fun (x,y) -> btos x ^ btos y

```

Therefore, the nested pair `(1,(false,true))` shows as `"(1,FT)"`:

```
 Show.find (Pair(Int, Pair(Bool,Bool))) (1,(false,true))
 (* - : string = "(1,FT)" *)

```

The library is extensible with user-defined data types, for example:

```
 type my_fancy_datatype = Fancy of int * string * (int -> string)

```

After registering the type with trep library and adding the printer

```
 let () = Show.register MyFancy @@ function Fancy(x,y,_) ->
 string_of_int x ^ "/" ^ y ^ "/" ^ "<fun>"

```

one can print rather complex data with fancy, with no further ado:

```
 Show.find (List(List(Pair(MyFancy,Int))))
 [[(Fancy(1,"fanci",fun x -> "x"),5)];[]]
 (* - : string = "[[(1/fanci/<fun>,5)];[]]" *)

```

As Mahboubi and Tassi would say, proof synthesis at work!

The next example is Haskell-like `Read`, to read (or, parse) values
of various types. Overloading here is resolved based on
the return type.

```
 module Read = MakeResolve(struct type 'a dict = Scanf.Scanning.in_channel -> 'a end)
 
 let () = Read.register Int (fun ch -> Scanf.bscanf ch "%d" Fun.id)
 let () = Read.register Bool (fun ch -> Scanf.bscanf ch "%B" Fun.id)
 let () = 
 let open Read in
 let pat : type b. b trep -> b dict option = function
 | Pair (tx,ty) -> 
 Some (fun ch -> Scanf.bscanf ch "(%r, %r)" (find tx) (find ty) (fun x y -> (x,y)))
 | _ -> None
 in 
 register_rule {pat}

```

Here is an example (the comment underneath shows the evaluation result):

```
 Read.find (Pair(Int,Pair(Bool,Bool))) (Scanf.Scanning.from_string "(1, (true, false))")
 (* - : int * (bool * bool) = (1, (true, false)) *)

```

The accompanying code shows the final example: `ReadShow`,
illustrating inheritance. This overloading function ensures that both
`show` and `read` are available for a particular type. Furthermore,
(if the programmer has defined them well) they are
coherent. `ReadShow` also provides the function `norm` which is the
composition of `read` and `show`: it converts a printing
representation of a value into a canonical form.

In conclusion, we have presented the library for canonical structures in
OCaml. The benefits (besides the educational):

- `#install_printer`--like facility, available to all programs
(not just the top-level), implemented as a plain self-contained
OCaml library with no compiler or other magic. 

- easy experimentation with type-class/implicit resolution strategies. 
Everything is `user-level', with no knowledge of (let alone changes to)
the compiler internals. Everything is above-the-board and typed:
whatever the resolution algorithm one may come up with, it would be good 
(or, at least, type-preserving).

Here are sample experiments to try: disallow overlapping and ensure at most 
one resolution; return the most-specific match rather than the
first match; implement backtracking; try out bottom-up 
Datalog-like evaluation (which helps ensure the
uniqueness of the resolution); implement 
`local' instances (canonical values that are used only within a
particular scope).

- when used in meta-program, i.e., as part of a code generator, 
the library becomes a viable method of implementing
implicits.

#### References

[canonical.ml](https://okmij.org/ftp/ML/canonical.ml) [13K]

The implementation of the library and the examples

[Type Representations](https://okmij.org/ftp/ML/canonical.html#trep)

[Session types without
sophistry](https://okmij.org/ftp/Computation/types.html#sessions)

An application in a large practical library.
The canonical structures are used to look up the code for
serializers and deserializers, to print types, and to implement
`infer` to infer session types of process fragments with an arbitrary
number of free endpoint variables.

 

## Canonical structures in meta-programming

We have presented the implementation of canonical structures at
user-level. Therefore, the look up of canonical values happens at
run-time -- rather than at compile time, as in type-class
resolution. The look-up failures are also reported at run-time. In
Coq, canonical structures are part of the type checker. A resolution
failure is hence a type checking error. Also, in Coq the user does
not have to explicitly specify the type to resolve on: it can almost
always be inferred.

The drawbacks of our canonical structures library also disappear if we
use it in a meta-program (code generator). Overloading resolution
errors reported at run-time of the *generator* are `compile-time'
errors from the point of view of the generated program. Our canonical
structures library then becomes a type-class/implicits facility, for
the generated code -- the facility, we can easily (re)program.

 

## Type Representations

A type representation is a value that represents a type. In OCaml, and
similar type-erasure languages, types are used only at
compile-time. At run-time, a function cannot find out precise types of
its arguments (and alter its behavior depending on those types). Yet
accepting as an argument values of different types and
processing them depending on their type is useful: for example, generic
printing. In OCaml such function should receive not just the value of
the argument but also some representation of its type. Type
representations are also needed for dynamics, heterogeneous
collections, type-safe cast, type-safe marshaling and
deserialization, etc.

Therefore, several type representation libraries have been developed
over the years, referenced below. They differ in how much they rely on
the compiler/run-time internals, how
many applications they include. Here we present one of the simplest
libraries. It is implemented in pure OCaml, with no dependence or even
knowledge of the OCaml internals, and without any unsafe operations. It is
extensible to arbitrary user-defined data types, also supporting
parameterized and abstract types. It is a pure-OCaml
version of Haskell's `Typeable`.

In our library, a type `t` is represented by the value of the type `t trep`, which is the (generalized) algebraic data type. It is extensible:

```
 type _ trep = ..

```

initially populated as follows (abbreviated):

```
 type _ trep += 
 | Unit : unit trep
 | Int : int trep
 | List : 'a trep -> 'a list trep
 | Fun : 'a trep * 'b trep -> ('a -> 'b) trep

```

The library also defines the type equality comparison

```
 val teq : type a b. a trep -> b trep -> (a,b) eq option

```

where `eq` is the type equality (propositional equality) witness:

```
 type (_,_) eq = Refl : ('a,'a) eq

```

That is, `teq` compares two type representations `t1 trep` and `t2 trep`. If they are equal, it returns the witness that `t1` and
`t2` are the same type, which could be used to safely cast
(inter-convert) the values of these types. Using OCaml internals,
`teq` may be implemented once and for all, efficiently, by comparing
run-time `trep` values. Our library however is above the board and
uses no internals magic. For that reason, the library provides the
operation to extend `teq` for newly defined types, illustrated later.

Unlike other libraries, `trep` offers no printing or constructor
introspection. These facilities are better implemented via
canonical structures (aka, `implicits for the masses'). It is
bare-bone, intended as the foundation for dynamics,
heterogeneous type-indexed collections and implicits for the masses:
programmable overloading resolution.

Here is the simple illustration: generic showing.

```
 val gshow : 'a trep -> 'a -> string

```

The function `gshow` takes a value and a representation of its type
and returns the string `showing' the value. The idea of the
pattern-matching on the type representation is clearly seen in the
following auxiliary:

```
 let gshow_init : type a. a trep -> a -> string option = fun t v ->
 match t with
 | Unit -> Some "()"
 | Int -> Some (string_of_int v)
 | Bool -> Some (string_of_bool v)
 ...

```

The function `gshow` can handle pairs, lists and option types
(the result of the expression is shown in the comments underneath):

```
 gshow (Pair (Int,Bool)) (1,true)
 (* - : string = "(1, true)" *)
 
 gshow (List (Pair (Int,Bool))) [(1,true); (2,false)]
 (* - : string = "[(1, true); (2, false)]" *)

```

It is also extensible for user-defined data types. For example, after
introducing a new data type

```
 type 'a myres = R of 'a * int | Err of string

```

and registering it with the trep library

```
 type _ trep += MyRes : 'a trep -> 'a myres trep
 
 let () = 
 let teq : type a b. a trep -> b trep -> (a,b) eq option = fun x y -> 
 match (x,y) with 
 | (MyRes x,MyRes y) ->(match teq x y with Some Refl-> Some Refl | _ -> None)
 | _ -> None
 in teq_extend {teq}

```

we may extend `gshow` 

```
 let () = 
 let gshow : type a. a trep -> a -> string option = function MyRes t ->
 (function R (x,i) -> Some ("R " ^ gshow (Pair (t,Int)) (x,i))
 | Err s -> Some ("Err " ^ s))
 | _ -> fun _ -> None
 in gshow_extend {gshow}

```

We now may show the values involving `myres`, among others

```
 let _ = gshow (Pair (Bool,MyRes (List Int))) (true,R ([1;2;3],4))
 (* - : string = "(true, R ([1; 2; 3], 4))" *)

```

We should stress that `gshow` is merely an illustration of the `trep`
library. Generic functions are more convenient to
define with the canonical structures facility, built upon `trep`.

#### Version

The current version is July 2019

#### References

Robert Harper and J. Gregory Morrisett:
Compiling Polymorphism Using Intensional Type Analysis. POPL 1995

One of the first papers on type representations.

[trep.ml](https://okmij.org/ftp/ML/trep.ml) [3K]

The complete code of the introduced trep library

[gshow.ml](https://okmij.org/ftp/ML/gshow.ml) [4K]

An illustration of the trep library: generic show

Jacques Garrigue and Grégoire Henry: Runtime types in OCaml

OCaml 2013: The OCaml Users and Developers Workshop

<[https://ocaml.org/meetings/ocaml/2013/proposals/runtime-types.pdf](https://ocaml.org/meetings/ocaml/2013/proposals/runtime-types.pdf)>

The classical paper on problems and difficult choices 
arising from type abstraction.

Ivan Gotovchits. Extensible and very efficient type
representations in the CMU Binary Analysis Project (BAP)

Messages on the caml-list, 4 Sep 2019

``What could be surprising is that the
universe of types actually grew quite large, that large that the linear
search in the registry is not an option for us anymore.... An
important lesson that we have learned is that treps should not only be
equality comparable but also ordered (and even hashable) so that we can
implement our registries as hash tables. It is also better to keep them
abstract so that we can later extend them without breaking user code (to
implement introspection as well as different resolution schemes)''

Type representations in Jane St. library

<[https://github.com/janestreet/base/blob/master/src/type_equal.mli](https://github.com/janestreet/base/blob/master/src/type_equal.mli)>

<[https://github.com/janestreet/typerep](https://github.com/janestreet/typerep)>

It is quite extensive, and relies on OCaml internals

Patrik Keller, Marc Lasson: LexiFi Runtime Types
OCaml 2020 Workshop

<[http://github.com/mirage/repr](http://github.com/mirage/repr)>

Type representation library from Mirage, with combinators
for generic programming

 

### Last updated May 14, 2021

This site's top page is [**http://okmij.org/ftp/**](http://okmij.org/ftp/)

oleg-at-okmij.org

Your comments, problem reports, questions are very welcome!

Generated by MarXere
