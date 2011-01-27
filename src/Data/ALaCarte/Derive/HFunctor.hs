{-# LANGUAGE TemplateHaskell #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Data.ALaCarte.Derive.HFunctor
-- Copyright   :  3gERP, 2010
-- License     :  AllRightsReserved
-- Maintainer  :  Tom Hvitved, Patrick Bahr, and Morten Ib Nielsen
-- Stability   :  unknown
-- Portability :  unknown
--
--
--------------------------------------------------------------------------------

module Data.ALaCarte.Derive.HFunctor
    ( instanceHFunctor
    )where

import Data.ALaCarte.Derive.Utils
import Data.ALaCarte.Multi.HFunctor
import Language.Haskell.TH
import qualified Prelude as P (mapM)
import Prelude hiding (mapM)
import Data.Maybe

iter 0 _ e = e
iter n f e = iter (n-1) f (f `appE` e)


instanceHFunctor :: Name -> Q [Dec]
instanceHFunctor fname = do
  TyConI (DataD _cxt name args constrs _deriving) <- abstractNewtypeQ $ reify fname
  let args' = init args
      fArg = VarT . tyVarBndrName $ last args'
      argNames = (map (VarT . tyVarBndrName) (init args'))
      complType = foldl AppT (ConT name) argNames
      classType = AppT (ConT ''HFunctor) complType
  constrs' <- P.mapM (mkPatAndVars . isFarg fArg . normalCon') constrs
  hfmapDecl <- funD 'hfmap (map hfmapClause constrs')
  return $ [InstanceD [] classType [hfmapDecl]]
      where isFarg fArg (constr, args) = (constr, map (`containsType'` fArg) args)
            filterVar _ nonFarg [] x  = nonFarg x
            filterVar farg _ [depth] x = farg depth x
            filterVar _ _ _ _ = error "functor variable occurring twice in argument type"
            filterVars args varNs farg nonFarg = zipWith (filterVar farg nonFarg) args varNs
            mkCPat constr varNs = ConP constr $ map mkPat varNs
            mkPat x = VarP x
            mkPatAndVars (constr, args) =
                do varNs <- newNames (length args) "x"
                   return (conE constr, mkCPat constr varNs,
                           (\ f g -> filterVars args varNs (\ d x -> f d (varE x)) (g . varE)),
                           any (not . null) args, map varE varNs, catMaybes $ filterVars args varNs (\d x -> Just (d, x)) (const Nothing))
            hfmapClause (con, pat,vars',hasFargs,_,_) =
                do fn <- newName "f"
                   let f = varE fn
                       fp = if hasFargs then VarP fn else WildP
                       vars = vars' (\d x -> iter d [|fmap|] f `appE` x) id
                   body <- foldl appE con vars
                   return $ Clause [fp, pat] (NormalB body) []