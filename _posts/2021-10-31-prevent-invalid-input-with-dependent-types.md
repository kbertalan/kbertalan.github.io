---
layout: post
title: Prevent invalid input with dependent types
tags:
  - idris
  - dependent types
  - type level programming
  - example
excerpt_separator: <!--more-->
---

As an application developer I've always wanted to enhance developer experience. The most common tool for this is a statically typed programming language.
It is fascinating what such programming languages can do in compile time, and what amount of issues they can prevent at runtime.

However most of these languages are limited to their own language domains, they require external tools or plugins to extend their capabilities.
In this post I would like to show you a simple problem in the server side web development domain, which can be solved with dependent types in idris programming language.

<!--more-->

#### The problem

We are developing a simple web framework to be able to serve web APIs and files. When a HTTP request arrives, our framework need to be able to select a route matching the requested resource from a predefined list of routes. In addition the routes can contain path variables, which need to be bound to variables.

In this example we will ignore the problem how to associate a handler function a matched route, and concentrate on how to implement the route selection only.

As we plan to make the users of the framework life easier we provide a function which can accept a route as string and provides another function which can replace a string based path with a proper path model if the path matches the route.

Let model this with the following types and function:

``` haskell
-- Fake HTTP request
public export
record Request p where
  constructor MkRequest
  path: p

public export
record Path where
  constructor MkPath
  raw : String
  params : List (String, String)
  rest : String

export
pattern : String -- route pattern as a String
  -> Request String -- HTTP request which path is not resolved to a route
  -> Maybe $ Request Path -- HTTP request which path is a resolved route
pattern str req = ?pattern_rhs
```
_See documentation of records [here](https://idris2.readthedocs.io/en/latest/tutorial/typesfuns.html#records)_

This is nice, but how should the `pattern` function behave, when the route pattern is invalid?

##### Defensive programming

Parse the route pattern and if it invalid, throw a runtime exception (panic in some languages).  The developer would notice the mistake only when running the code.

Fortunatelly we don't have exceptions in idris, so this option is not valid in our example.

##### Accept only valid patterns by changing the pattern model

We also can replace `String` parameter to a `Pattern` model, and let the developer construct it via custom expressions.

This would expose our route pattern model to the outside and we would need to work hard to make it usable DSL.

While this is a viable option I would prefer to use a more compact representation and stick to the original plan to use `String` for patterns.

##### Use Nothing for signaling the invalid route

We also can choose to use Nothing when the route is invalid. We either change the `pattern` function to this:

``` haskell
export
pattern : String -- route pattern as a String
  -> Maybe (
    Request String -- HTTP request which path is not resolved to a route
    -> Maybe $ Request Path -- HTTP request which path is a resolved route
  )
pattern str = ?pattern_rhs
```

or compute Nothing when we receive the request.

The first option requires the developer to handle route syntax errors when all routes are valid.

The second is a lie, and it cannot be distinguished from the case when a valid route does not match an incoming request's path. So I consider this more error prone.

##### Let the compiler exclude the invalid routes

What if the compiler would understand our route pattern syntax and deny compilation when it has invalid value?

This is what I will proceed with using idris. (In other programming languages you might need to develop some plugins to the compiler to achieve the same results.)

#### Route syntax

Let me show an example which demonstrates the basics of the route pattern syntax we will implement:

```
    "/user/{id}/post/{post-id}/*"
     |    |  | |    |    |    | \
     |    |  | |    |    |    |  \
     \    /  | \   /     |    |   \
    literal  | literal   | literal \
             |           |          \
         parameter    parameter    rest
```

A literal is any character sequence which need to be matched exactly as written in the route pattern.

A parameter is denoted with curly braces which contains the parameter name. The param will match the character sequence ended by the next literal's first character, or the end of the input path.

The rest of the pattern is a special parameter denoted with asterics in the pattern, this will match any character sequence till end of the path.

#### Route model

We will introduce a list of pattern elements (literal, parameter and rest) as our internal model, and a `parse` function with some error cases to handle valid and invalid inputs.
The below types are showing our model:

``` haskell
data Elem : Type where
  Literal : List Char -> Elem
  Param : List Char -> Elem
  Rest : Elem

public export
data ParseError
  = EmptyPattern
  | ParamShouldFollowALiteral String (List Elem)
  | RestShouldFollowALiteral String (List Elem)
  | ParamAlreadyDefined String (List Elem)
  | ParamEmpty String (List Elem)
  | UnclosedParam String (List Elem)
  | InvalidStartCharInParam Char (List Elem)
  | InvalidCharInParam Char (List Elem)
  | RestShouldBeLast String (List Elem)

export
data ParsedPattern : (0 s : String) -> Type where
  MkParsedPattern : List Elem -> ParsedPattern s

public export
parse : (s : String) -> Either ParseError (ParsedPattern s)
parse s = ?parse_rhs
```

An external module cannot access the `Elem` type, nor the `MkParsedPattern` data constructor, therefore the only way for other modules to construct a `ParsedPattern` via the `parse` function. This `parse` function behaves like a smart constructor in this case.

The `parse` function constructs a type which is dependent on the route pattern it parses, because `ParsedPattern` type is indexed by the route string. A `ParsedPattern "/static/*"` type is depending on the string pattern, however that `String` type parameter is erased in runtime (as you can see from the 0 quantity). This string index on `ParsedPattern` is not necessary for our goal, but it is nice to have.

Also note that `parse` function is annotated with `public export`, which exposes its type and definition (implementation) as well to other modules. This is necessary if we need to use it in compile time.

#### Parse route for pattern function

First let assume we have everything at hand, the path from the HTTP request and a valid, parsed route pattern. Let's define a function to do the matching and compute a resolved `Path` value for us, if route matches the path:

``` haskell
matcher : (s : String) -- path from HTTP request
  -> ParsedPattern str -- valid, parsed route, indexed by 'str' route
  -> Maybe Path
matcher s (MkParsedPattern ls) = ?matcher_rhs
```

This `matcher` function contains a regular implementation of the match logic. Using this we can define our `pattern` function:

``` haskell
export
pattern :
  (str : String)
  -> Request String 
  -> Maybe $ Request Path
pattern str req =
  case matcher req.path ?parsedPattern of
     Just p => Just $ { path := p } req
     Nothing => Nothing
```
_See record update syntax details at [updates documentation](https://idris2.readthedocs.io/en/latest/updates/updates.html#record-updates)_

But our task is to get the compiler to provide us the missing `parsedPattern`. It is easier then someone would assume.

To run automatically our parse method, we will introduce a new implicit parameter called `parsed` and initialize with the parsed route. This default value will still be running in runtime, though. And it can still have a `Left` value. We don't really want to handle the error case at runtime.

To convince the compiler, we need to provide a proof that the parsed pattern is a `Right` value. For this we will use the `IsRight` data type and pass the parse result to it as a parameter. The result is that the parsing expression will be evaluated at compile time to find out wether the result is `Left` or `Right`.

The only task is to pattern match on the `parsed` implicit parameter and extract the `ParsedPattern str` value from it:

``` haskell
export
pattern :
  (str : String)
  -> {default (Path.parse str) parsed : _} -- initialize 'parsed' with the parse result, it's type is determined by the function type
  -> {auto 0 ok : IsRight parsed } -- prove that the result is a 'Right' value
  -> Request String 
  -> Maybe $ Request Path
pattern str {parsed = (Right parsedPattern)} req = -- pattern match
  case matcher req.path parsedPattern of
     Just p => Just $ { path := p } req
     Nothing => Nothing
```
_See more details on [auto implicit arguments](https://idris2.readthedocs.io/en/latest/tutorial/miscellany.html#default-implicit-arguments)
and [default implicit arguments](https://idris2.readthedocs.io/en/latest/tutorial/miscellany.html#default-implicit-arguments) in the idris crash course_

The resulting function is covering all possible inputs, and we don't need to provide implementation to handle the `Left` case.

If you are an idris pacticioner, then you will notice that `IsRight` is not available in idris at the time of writing of this post. It is similar to the `IsJust` type defined in `Data.Maybe` module of the `base` package, and it looks like this:

``` haskell
public export
data IsRight : Either a b -> Type where
  ItIsRight : IsRight (Right x) -- there is only a single constructor accepting 'Right' values only

export
Uninhabited (IsRight (Left x)) where
  uninhabited ItIsRight impossible -- this prevents idris to allow 'Left' value in an 'IsRight' type
```

#### Testing some cases

The following examples all pass (but sometimes results in a Nothing as the route is not matching the path):

``` haskell
  pattern "/" $ MkRequest "/about.html"
  pattern "/about.{ext}" $ MkRequest "/about.html"
  pattern "/{file}.html" $ MkRequest "/post.html"
  pattern "/user/{id}" $ MkRequest "/"
  pattern "/user/{id}/profile" $ MkRequest "/user/423/profile"
  pattern "/user/{id}/post/{post-id}" $ MkRequest "/user/423/post/92732"
  pattern "/static/*" $ MkRequest "/static/assets/main.css"
  pattern ("/" <+> "static" <+> "/*") $ MkRequest "/index.html"
```

The below examples are failing, due to compile error (as you can see the compile errors are included as comments):

``` haskell
-- Error: While processing right hand side of main. Can't find an implementation for (IsRight (Left EmptyPattern).
  pattern "" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (Left (ParamEmpty "{}" [Literal ['/']])).
  pattern "/{}" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (Left (ParamAlreadyDefined "id" [Literal ['/'],
--                                             Param ['i', 'd'],
--                                             Literal ['/', 'o', 't', 'h', 'e', 'r', '/']])).
  pattern "/{id}/other/{id}" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (parse (prim__strAppend (prim__strAppend "/" static) "/*")).
  let static = "static"
  in pattern ("/" <+> static <+> "/*") $ MkRequest "/index.html"
```

If you want to see these examples, and the rest of the implementation in action, you can find the source code on [github](https://github.com/kbertalan/kbertalan.github.io/tree/main/assets/posts/idris).

#### Conclusion

Dependently typed programming can be straigthforward, in our case we had to add two implicit parameters to a function, pattern match on one of them, and make the definition of another function available for other modules.

However there are also consequences, this works the best on static strings. If you construct the route pattern using other functions, or from bounded values in runtime, then the compiler cannot normalize the value anymore in compile time.

In those cases the developer will need to bring the evidence of the route pattern validity and deal with the error case, which is not a bad idea anyway.

__Updated at 2021-11-01__: changes based on feedback of [Andor Pénzes](https://github.com/andorp)
