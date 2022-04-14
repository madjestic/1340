{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Arrows #-}

module Solvable
  ( Solver (..)
  , preTransformer
  , preTransformer'
  , translate
  , rotate
  , toSolver
  ) where

import Control.Lens      hiding (Identity)
import GHC.Float
import Linear.Matrix     hiding (identity)
import Linear.Matrix     as LM
import Linear.V3
import Linear.V4
import Linear.Quaternion hiding (rotate)
import FRP.Yampa         hiding (identity)

import Graphics.RedViz.Utils
-- import Utils

import Debug.Trace as DT

data Solver =
     Identity
  |  PreTranslate
     {
       _txyz   :: V3 Double
     }
  |  Translate
     {
       _txyz   :: V3 Double
     }
  |  PreRotate
     {
       _pivot :: V3 Double
     , _ypr   :: V3 Double
     }
  |  Rotate
     {
       _pivot :: V3 Double
     , _ypr   :: V3 Double
     }
  |  RotateConst
     {
       _pivot :: V3 Double
     , _ypr   :: V3 Double
     }
  |  Scale
     {
       _sxyz   :: V3 Double
     }
  |  LOD
     {
       _models :: [FilePath]
     }
  |  Gravity
    {
      _idxs :: [Int]
    } deriving Show
$(makeLenses ''Solver)

toSolver :: (String, [Double]) -> Solver
toSolver (solver, parms) =
  --case DT.trace ("toSolver.solver :" ++ show solver) solver of
  case solver of
    "pretranslate" -> PreTranslate (toV3 parms)
    "translate"    -> Translate    (toV3 parms)
    "prerotate"    -> PreRotate    (toV3 $ take 3 parms) (toV3 $ drop 3 parms)
    "rotate"       -> Rotate       (toV3 $ take 3 parms) (toV3 $ drop 3 parms)
    "rotateconst"  -> RotateConst  (toV3 $ take 3 parms) (toV3 $ drop 3 parms)
    "gravity"      -> Gravity      (double2Int <$> parms)
    "identity"     -> Identity
    _              -> Identity

preTransformer :: Solver -> M44 Double -> M44 Double
preTransformer solver mtx0 = mtx
  where
    mtx = case solver of
      PreTranslate v0    -> preTranslate mtx0 v0
      PreRotate pv0 ypr1 -> preRotate mtx0 pv0 ypr1
      Identity           -> Solvable.identity mtx0
      _                  -> mtx0

preTransformer' :: Solver -> (M44 Double, V3 Double) -> (M44 Double, V3 Double)
preTransformer' solver (mtx0, ypr0) = (mtx, ypr)
  where
    (mtx, ypr) = case solver of
      PreTranslate v0    -> preTranslate' mtx0 v0
      PreRotate pv0 ypr1 -> preRotate' mtx0 pv0 ypr1
      Identity           -> Solvable.identity' mtx0
      _                  -> (mtx0, V3 0 0 0)

identity :: M44 Double -> M44 Double
identity mtx0 = mtx
  where
    mtx =
      mkTransformationMat
        rot
        tr
        where
          rot = view _m33 mtx0
          tr  = view (_w._xyz) mtx0

identity' :: M44 Double -> (M44 Double, V3 Double)
identity' mtx0 = (mtx, ypr)
  where
    ypr = V3 0 0 0
    mtx =
      mkTransformationMat
        rot
        tr
        where
          rot = view _m33 mtx0
          tr  = view (_w._xyz) mtx0

preTranslate :: M44 Double -> V3 Double -> M44 Double
preTranslate mtx0 v0 = mtx
  where
    mtx =
      mkTransformationMat
        rot
        tr
        where
          rot = view _m33 mtx0
          tr  = v0 + view (_w._xyz) mtx0

preTranslate' :: M44 Double -> V3 Double -> (M44 Double, V3 Double)
preTranslate' mtx0 v0 = (mtx, ypr)
  where
    ypr = V3 0 0 0
    mtx =
      mkTransformationMat
        rot
        tr
        where
          rot = view _m33 mtx0
          tr  = v0 + view (_w._xyz) mtx0

-- TODO: preRotate mtx0 _pv0_ ypr0 = mtx -- pv0 - rotation origin
preRotate :: M44 Double -> V3 Double -> V3 Double -> M44 Double
preRotate mtx0 _ ypr0 = mtx
    where
      mtx =
          mkTransformationMat
            rot
            tr
            where
              rot =
                view _m33 mtx0
                !*! fromQuaternion (axisAngle (view _x (view _m33 mtx0)) (view _x ypr0)) -- yaw
                !*! fromQuaternion (axisAngle (view _y (view _m33 mtx0)) (view _y ypr0)) -- pitch
                !*! fromQuaternion (axisAngle (view _z (view _m33 mtx0)) (view _z ypr0)) -- roll
              tr  = view (_w._xyz) mtx0

preRotate' :: M44 Double -> V3 Double -> V3 Double -> (M44 Double, V3 Double)
preRotate' mtx0 _ ypr1 = (mtx, ypr1)
    where
      mtx =
          mkTransformationMat
            rot
            tr
            where
              rot =
                view _m33 mtx0
                !*! fromQuaternion (axisAngle (view _x (view _m33 mtx0)) (view _x ypr1)) -- yaw
                !*! fromQuaternion (axisAngle (view _y (view _m33 mtx0)) (view _y ypr1)) -- pitch
                !*! fromQuaternion (axisAngle (view _z (view _m33 mtx0)) (view _z ypr1)) -- roll
              tr  = view (_w._xyz) mtx0

translate :: M44 Double -> V3 Double -> SF () (M44 Double)
translate mtx0 v0 =
  proc () -> do
    --tr' <- (V3 0 0 0 +) ^<< integral -< v0 -- maybe that's why translation is reset?
    --tr' <- ((DT.trace ("translate.translation : " ++ show (mtx0 ^. translation))mtx0 ^. translation) +) ^<< integral -< v0 -- maybe that's why translation is reset?
    tr' <- (mtx0 ^. translation +) ^<< integral -< v0 -- maybe that's why translation is reset?
    let mtx =
          mkTransformationMat
            (view _m33 mtx0)
            tr'

    returnA -< mtx

rotate :: M44 Double -> V3 Double -> V3 Double -> V3 Double -> SF () (M44 Double, V3 Double)
rotate mtx0 _ ypr0 ypr1 =
  proc () -> do
    -- ypr' <- (V3 0 0 0 +) ^<< integral -< ypr0
    ypr' <- (ypr0 +) ^<< integral -< ypr1
    let mtx =
          mkTransformationMat
            rot
            tr
            where
              -- rot =
              --   view _m33 mtx0
              --   !*! fromQuaternion (axisAngle (view _x (view _m33 mtx0)) (view _x ypr')) -- yaw
              --   !*! fromQuaternion (axisAngle (view _y (view _m33 mtx0)) (view _y ypr')) -- pitch
              --   !*! fromQuaternion (axisAngle (view _z (view _m33 mtx0)) (view _z ypr')) -- roll
              rot =
                (LM.identity :: M33 Double)
                !*! fromQuaternion (axisAngle (view _x (LM.identity :: M33 Double)) (view _x ypr')) -- yaw
                !*! fromQuaternion (axisAngle (view _y (LM.identity :: M33 Double)) (view _y ypr')) -- pitch
                !*! fromQuaternion (axisAngle (view _z (LM.identity :: M33 Double)) (view _z ypr')) -- roll
              
              tr  = (view (_w._xyz)) mtx0
    returnA -< (mtx, ypr')
