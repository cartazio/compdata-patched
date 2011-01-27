{-# LANGUAGE TemplateHaskell #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.ALaCarte.Derive.SmartMConstructors
-- Copyright   :  3gERP, 2011
-- License     :  AllRightsReserved
-- Maintainer  :  Patrick Bahr, Tom Hvitved
-- Stability   :  unknown
-- Portability :  unknown
--
--
--------------------------------------------------------------------------------

module Data.ALaCarte.Derive.SmartMConstructors 
    (smartMConstructors) where



import Language.Haskell.TH hiding (Cxt)
import Data.ALaCarte.Derive.Utils
import Data.ALaCarte.Multi.Sum
import Data.ALaCarte.Multi.Term

import Control.Monad


smartMConstructors :: Name -> Q [Dec]
smartMConstructors fname = do
    TyConI (DataD _cxt tname targs constrs _deriving) <- abstractNewtypeQ $ reify fname
    let cons = map abstractConType constrs
    liftM concat $ mapM (genSmartConstr (map tyVarBndrName targs) tname) cons
        where genSmartConstr targs tname (name, args) = do
                let bname = nameBase name
                genSmartConstr' targs tname (mkName $ 'i' : bname) name args
              genSmartConstr' targs tname sname name args = do
                varNs <- newNames args "x"
                let pats = map varP varNs
                    vars = map varE varNs
                    val = foldl appE (conE name) vars
                    sig = genSig targs tname sname args
                    function = [funD sname [clause pats (normalB [|inject $val|]) []]]
                sequence $ sig ++ function
              genSig targs tname sname 0 = (:[]) $ do
                fvar <- newName "f"
                hvar <- newName "h"
                avar <- newName "a"
                ivar <- newName "i"
                let targs' = init $ init targs
                    vars = fvar:hvar:avar:ivar:targs'
                    f = varT fvar
                    h = varT hvar
                    a = varT avar
                    i = varT ivar
                    ftype = foldl appT (conT tname) (map varT targs')
                    constr = classP ''(:<<:) [ftype, f]
                    typ = foldl appT (conT ''Cxt) [h, f, a, i]
                    typeSig = forallT (map PlainTV vars) (sequence [constr]) typ
                sigD sname typeSig
              genSig _ _ _ _ = []