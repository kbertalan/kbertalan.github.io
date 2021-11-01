---
layout: post
title: Prevent invalid input with dependent types - a fixed solution
tags:
  - idris
  - dependent types
  - type level programming
  - example
excerpt_separator: <!--more-->
---

[Guillaume Allais](https://gallais.github.io/) highlighted for the [previous post]({% link _posts/2021-10-31-prevent-invalid-input-with-dependent-types.md %}), that the `pattern` function allows the caller to specify other value for the `parsed` implicit parameter by overriding the default value.

So it is possible to call `pattern` with a route pattern string `"/*"` and pass in a `ParsedPattern "/other"` parameter, which would result in an inconsistent behaviour.

<!--more-->

[Andor Pénzes](https://github.com/andorp/) mentioned that the usage of `default` in the previous solution is a code-smell, and he was kind to investigate a better solution.

Let's see the updated code based on his investigation:

``` haskell
export
pattern :
  (str : String)
  -> {auto 0 ok : IsRight (Path.parse str)} -- evaluate the route pattern parse at compile time to determine whether it is Right
  -> Request String 
  -> Maybe $ Request Path
pattern str req with (Path.parse str) -- evaluate the route pattern parsing logic in runtime
  _ | Right parsedPattern = -- pattern match on the result
    case matcher req.path parsedPattern of
       Just p => Just $ { path := p } req
       Nothing => Nothing
```
_See the `with` clause documentation at the [crash course](https://idris2.readthedocs.io/en/latest/tutorial/views.html#the-with-rule-matching-intermediate-values), and the updated syntax in the [changelog](https://github.com/idris-lang/Idris2/blob/main/CHANGELOG.md#language-changes-1)._

This solution is preventing the issue and has the same result as described in the earlier post. The same examples have the same results too.

This implementation is also covering all cases, as the `IsRight` proof and the fact that `Path.parse` is pure guarantees that `Path.parse str` evaluated in runtime result in the same value what the compiler calculated.

The updated code can be found at [github](https://github.com/kbertalan/kbertalan.github.io/tree/main/assets/posts/idris-fix).
