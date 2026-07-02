{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedLists #-}

module API.Docs.Syntax.Types where

import Data.List.NonEmpty (NonEmpty)
import Data.Semigroup
import Data.String

type ExprParam = String

data Expr
  = Concat (NonEmpty Expr)
  | Const String
  | Param ExprParam
  | Optional Expr Expr ExprParam
  | Choice ExprParam (NonEmpty (String, Expr)) Expr
  | Join Char ExprParam
  | Json ExprParam
  | OnOff ExprParam
  | OnOffParam String ExprParam (Maybe Bool)
  deriving (Eq, Show)

isConst :: Expr -> Bool
isConst = \case
  Const _ -> True
  _ -> False

hasParams :: Expr -> Bool
hasParams = \case
  Concat es -> any (hasParams) es
  Const _ -> False
  Param _ -> True
  Optional {} -> True
  Choice {} -> True
  Join {} -> True
  Json _ -> True
  OnOff _ -> True
  OnOffParam {} -> True

instance IsString Expr where fromString = Const

instance Semigroup Expr where
  sconcat = Concat
  x <> y = Concat [x, y]
