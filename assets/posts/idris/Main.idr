module Main

import Data.String
import Path

print : Maybe (Request Path) -> IO ()
print Nothing = putStrLn "Input is not matching pattern\n"
print (Just res) = do
  putStrLn "Input \{res.path.raw} has matched pattern"
  for_ res.path.params $ \(param, value) => do
    putStrLn "\t\{param} := \{value}"
  unless (null res.path.rest) $ putStrLn "\trest value := \{res.path.rest}"
  putStrLn ""

main : IO ()
main = do

  print $ pattern "/" $ MkRequest "/about.html"
  print $ pattern "/about.{ext}" $ MkRequest "/about.html"
  print $ pattern "/{file}.html" $ MkRequest "/post.html"
  print $ pattern "/user/{id}" $ MkRequest "/"
  print $ pattern "/user/{id}/profile" $ MkRequest "/user/423/profile"
  print $ pattern "/user/{id}/post/{post-id}" $ MkRequest "/user/423/post/92732"
  print $ pattern "/static/*" $ MkRequest "/static/assets/main.css"
  print $ pattern ("/" <+> "static" <+> "/*") $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for (IsRight (Left EmptyPattern).
--  print $ pattern "" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (Left (ParamEmpty "{}" [Literal ['/']])).
--  print $ pattern "/{}" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (Left (ParamAlreadyDefined "id" [Literal ['/'],
--                                             Param ['i', 'd'],
--                                             Literal ['/', 'o', 't', 'h', 'e', 'r', '/']])).
--  print $ pattern "/{id}/other/{id}" $ MkRequest "/index.html"

-- Error: While processing right hand side of main. Can't find an implementation for IsRight (parse (prim__strAppend (prim__strAppend "/" static) "/*")).
--  let static = "static"
--  print $ pattern ("/" <+> static <+> "/*") $ MkRequest "/index.html"
