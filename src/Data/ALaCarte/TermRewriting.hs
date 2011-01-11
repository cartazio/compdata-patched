{-# LANGUAGE RankNTypes, GADTs #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.ALaCarte.TermRewriting
-- Copyright   :  3gERP, 2010
-- License     :  AllRightsReserved
-- Maintainer  :  Tom Hvitved, Patrick Bahr, and Morten Ib Nielsen
-- Stability   :  unknown
-- Portability :  unknown
--
-- This module defines term rewriting systems (TRSs) using data types
-- a la carte.
--
--------------------------------------------------------------------------------

module Data.ALaCarte.TermRewriting where

import Prelude hiding (any)

import Data.ALaCarte.Term
import Data.ALaCarte.Sum
import Data.ALaCarte.Algebra
import Data.ALaCarte.Equality
import Data.ALaCarte.Matching
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Maybe
import Data.Foldable

import Control.Monad


{-| This type represents /recursive program schemes/.  -}

type RPS f g  = TermHom f g

type Var = Int

{-| This type represents term rewrite rules from signature @f@ to
signature @g@ over variables of type @v@ -}

type Rule f g v = (Context f v, Context g v)


{-| This type represents term rewriting systems (TRSs) from signature
@f@ to signature @g@ over variables of type @v@.-}

type TRS f g v = [Rule f g v]

type Step t = t -> Maybe t
type BStep t = t -> (t,Bool)

{-| This function tries to match the given rule against the given term
(resp. context in general) at the root. If successful, the function
returns the right hand side of the rule and the matching
substitution. -}

matchRule ::  (Ord v, EqF f, Eq a, Functor f, Foldable f)
          => Rule f g v -> Cxt h f a -> Maybe (Context g v, Map v (Cxt h f a))
matchRule (lhs,rhs) t = do
  subst <- matchCxt lhs t
  return (rhs,subst)

matchRules :: (Ord v, EqF f, Eq a, Functor f, Foldable f)
           => TRS f g v -> Cxt h f a -> Maybe (Context g v, Map v (Cxt h f a))
matchRules trs t = listToMaybe $ catMaybes $ map (`matchRule` t) trs

{-| This function tries to apply the given rule at the root of the
given term (resp. context in general). If successful, the function
returns the result term of the rewrite step; otherwise @Nothing@. -}

applyRule :: (Ord v, EqF f, Eq a, Functor f, Foldable f)
          => Rule f f v -> Step (Cxt h f a)
applyRule rule t = do 
  (res, subst) <- matchRule rule t
  return $ substHoles' res subst

{-| This function tries to apply one of the rules in the given TRS at
the root of the given term (resp. context in general) by trying each
rule one by one using 'applyRule' until one rule is applicable. If no
rule is applicable @Nothing@ is returned. -}

applyTRS :: (Ord v, EqF f, Eq a, Functor f, Foldable f)
         => TRS f f v -> Step (Cxt h f a)
applyTRS trs t = listToMaybe $ catMaybes $ map (`applyRule` t) trs


{-| This is an auxiliary function that turns function @f@ of type @(t
-> Maybe t)@ into functions @f'@ of type @t -> (t,Bool)@. @f' x@
evaluates to @(y,True)@ if @f x@ evaluates to @Just y@, and to
@(x,False)@ if $f x@ evaluates to @Nothing@. This function is useful
to change the output of functions that apply rules such as
'applyTRS'-}

bStep :: Step t -> BStep t
bStep f t = case f t of
                Nothing -> (t, False)
                Just t' -> (t',True)

{-| This function performs a parallel reduction step by trying to
apply rules of the given system to all outermost redexes. If the given
term contains no redexes, @Nothing@ is returned. -}

parTopStep :: (Ord v, EqF f, Eq a, Foldable f, Functor f)
           => TRS f f v -> Step (Cxt h f a)
parTopStep _ Hole{} = Nothing
parTopStep trs c@(Term t) = tTop `mplus` tBelow'
    where tTop = applyTRS trs c
          tBelow = fmap (bStep $ parTopStep trs) t
          tAny = any snd tBelow
          tBelow'
              | tAny = Just $ Term $ fmap fst tBelow
              | otherwise = Nothing

{-| This function performs a parallel reduction step by trying to
apply rules of the given system to all outermost redexes and then
recursively in the variable positions of the redexes. If the given
term does not contain any redexes, @Nothing@ is returned. -}

parallelStep :: (Ord v, EqF f, Eq a,Foldable f, Functor  f)
             => TRS f f v -> Step (Cxt h f a)
parallelStep _ Hole{} = Nothing
parallelStep trs c@(Term t) =
    case matchRules trs c of
      Nothing 
          | anyBelow -> Just $ Term $ fmap fst below
          | otherwise -> Nothing
        where below = fmap (bStep $ parallelStep trs) t 
              anyBelow = any snd below
      Just (rhs,subst) -> Just $ substHoles' rhs substBelow
          where rhsVars = Set.fromList $ toList rhs
                substBelow = Map.mapMaybeWithKey apply subst
                apply v t
                    | Set.member v rhsVars = Just $ fst $ bStep (parallelStep trs) t
                    | otherwise = Nothing
                

{-| This function applies the given reduction step repeatedly until a
normal form is reached. -}

reduce :: Step t -> t -> t
reduce s t = case s t of
               Nothing -> t
               Just t' -> reduce s t'