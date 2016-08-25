-- |
-- Module      : Math.LinearMap.Category
-- Copyright   : (c) Justus Sagemüller 2016
-- License     : GPL v3
-- 
-- Maintainer  : (@) sagemueller $ geo.uni-koeln.de
-- Stability   : experimental
-- Portability : portable
-- 


{-# LANGUAGE CPP                  #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE StandaloneDeriving   #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE UnicodeSyntax        #-}

module Math.LinearMap.Category (
            -- * Linear maps
            -- $linmapIntro

            -- ** Function implementation
              LinearFunction (..), (-+>)(), Bilinear
            -- ** Tensor implementation
            , LinearMap (..), (+>)()
            , (⊕), (>+<)
            -- * Tensor spaces
            , Tensor (..), (⊗)(), (⊗)
            -- * Norms
            -- $metricIntro
            , Norm(..)
            , spanNorm
            , euclideanNorm
            , (|$|)
            , normSq
            , (<$|)
            , normSpanningSystem
            -- ** Variances
            , Variance, spanVariance
            -- ** Utility
            , densifyNorm
            -- * Solving linear equations
            , (\$), pseudoInverse
            -- * Eigenvalue problems
            , constructEigenSystem
            , roughEigenSystem
            , Eigenvector(..)
            -- * The classes of suitable vector spaces
            -- ** Tensor products
            , TensorSpace (..)
            -- ** Functionals / linear maps
            , LinearSpace (..)
            -- ** Orthonormal systems
            , SemiInner (..), cartesianDualBasisCandidates
            -- ** Finite baseis
            , FiniteDimensional (..)
            -- * Utility
            -- ** Linear primitives
            , addV, scale, inner, flipBilin, bilinearFunction
            -- ** Hilbert space operations
            , DualSpace, riesz, coRiesz, showsPrecAsRiesz, (.<)
            -- ** Constraints synonyms
            , LSpace, Num', Num'', Num''', Fractional', Fractional''
            ) where

import Math.LinearMap.Category.Class
import Math.LinearMap.Category.Instances
import Math.LinearMap.Asserted

import Data.Tree (Tree(..), Forest)
import Data.List (sortBy, foldl')
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Ord (comparing)
import Data.List (maximumBy)
import Data.Foldable (toList)

import Data.VectorSpace
import Data.Basis

import Prelude ()
import qualified Prelude as Hask

import Control.Category.Constrained.Prelude hiding ((^))
import Control.Arrow.Constrained

import Data.VectorSpace.Free
import Math.VectorSpace.ZeroDimensional
import qualified Linear.Matrix as Mat
import qualified Linear.Vector as Mat
import Control.Lens ((^.))

import Numeric.IEEE

-- $linmapIntro
-- This library deals with linear functions, i.e. functions @f :: v -> w@
-- that fulfill
-- 
-- @
--   f $ μ 'Data.VectorSpace.^*' u 'Data.AdditiveGroup.^+^' v ≡ μ ^* f u ^+^ f v    ∀ μ :: 'Scalar' v
-- @
-- 
-- Such functions form a cartesian monoidal category (in maths called 
-- <https://en.wikipedia.org/wiki/Category_of_modules#Example:_the_category_of_vector_spaces VectK>).
-- This is implemented by 'Control.Arrow.Constrained.PreArrow', which is the
-- preferred interface for dealing with these mappings. The basic
-- “matrix operations” are then:
-- 
-- * Identity matrix: 'Control.Category.Constrained.id'
-- * Matrix addition: 'Data.AdditiveGroup.^+^' (linear maps form an ordinary vector space)
-- * Matrix-matrix multiplication: 'Control.Category.Constrained.<<<'
--     (or '>>>' or 'Control.Category.Constrained..')
-- * Matrix-vector multiplication: 'Control.Arrow.Constrained.$'
-- * Vertical matrix concatenation: 'Control.Arrow.Constrained.&&&'
-- * Horizontal matrix concatenation: '⊕' (aka '>+<')
-- 
-- But linear mappings need not necessarily be implemented as matrices:




-- | 'SemiInner' is the class of vector spaces with finite subspaces in which
--   you can define a basis that can be used to project from the whole space
--   into the subspace. The usual application is for using a kind of
--   <https://en.wikipedia.org/wiki/Galerkin_method Galerkin method> to
--   give an approximate solution (see '\$') to a linear equation in a possibly
--   infinite-dimensional space.
-- 
--   Of course, this also works for spaces which are already finite-dimensional themselves.
class LSpace v => SemiInner v where
  -- | Lazily enumerate choices of a basis of functionals that can be made dual
  --   to the given vectors, in order of preference (which roughly means, large in
  --   the normal direction.) I.e., if the vector @𝑣@ is assigned early to the
  --   dual vector @𝑣'@, then @(𝑣' $ 𝑣)@ should be large and all the other products
  --   comparably small.
  -- 
  --   The purpose is that we should be able to make this basis orthonormal
  --   with a ~Gaussian-elimination approach, in a way that stays numerically
  --   stable. This is otherwise known as the /choice of a pivot element/.
  -- 
  --   For simple finite-dimensional array-vectors, you can easily define this
  --   method using 'cartesianDualBasisCandidates'.
  dualBasisCandidates :: [(Int,v)] -> Forest (Int, DualVector v)

cartesianDualBasisCandidates
     :: [DualVector v]  -- ^ Set of canonical basis functionals.
     -> (v -> [ℝ])      -- ^ Decompose a vector in /absolute value/ components.
                        --   the list indices should correspond to those in
                        --   the functional list.
     -> ([(Int,v)] -> Forest (Int, DualVector v))
                        -- ^ Suitable definition of 'dualBasisCandidates'.
cartesianDualBasisCandidates dvs abss vcas = go 0 sorted
 where sorted = sortBy (comparing $ negate . snd . snd)
                       [ (i, (av, maximum av)) | (i,v)<-vcas, let av = abss v ]
       go k ((i,(av,_)):scs)
          | k<n   = Node (i, dv) (go (k+1) [(i',(zeroAt j av',m)) | (i',(av',m))<-scs])
                                : go k scs
        where (j,_) = maximumBy (comparing snd) $ zip jfus av
              dv = dvs !! j
       go _ _ = []
       
       jfus = [0 .. n-1]
       n = length dvs
       
       zeroAt :: Int -> [ℝ] -> [ℝ]
       zeroAt _ [] = []
       zeroAt 0 (_:l) = (-1/0):l
       zeroAt j (e:l) = e : zeroAt (j-1) l

instance (Fractional'' s, SemiInner s) => SemiInner (ZeroDim s) where
  dualBasisCandidates _ = []
instance (Fractional'' s, SemiInner s) => SemiInner (V0 s) where
  dualBasisCandidates _ = []

(<.>^) :: LSpace v => DualVector v -> v -> Scalar v
f<.>^v = (applyDualVector$f)$v

orthonormaliseDuals :: (SemiInner v, LSpace v, Fractional'' (Scalar v))
                          => [(v, DualVector v)] -> [(v,DualVector v)]
orthonormaliseDuals [] = []
orthonormaliseDuals ((v,v'₀):ws)
          = (v,v') : [(w, w' ^-^ (w'<.>^v)*^v') | (w,w')<-wssys]
 where wssys = orthonormaliseDuals ws
       v'₁ = foldl' (\v'i (w,w') -> v'i ^-^ (v'i<.>^w)*^w') v'₀ wssys
       v' = v'₁ ^/ (v'₁<.>^v)

dualBasis :: (SemiInner v, LSpace v, Fractional'' (Scalar v)) => [v] -> [DualVector v]
dualBasis vs = snd <$> orthonormaliseDuals (zip' vsIxed candidates)
 where zip' ((i,v):vs) ((j,v'):ds)
        | i<j   = zip' vs ((j,v'):ds)
        | i==j  = (v,v') : zip' vs ds
       zip' _ _ = []
       candidates = sortBy (comparing fst) . findBest
                             $ dualBasisCandidates vsIxed
        where findBest [] = []
              findBest (Node iv' bv' : _) = iv' : findBest bv'
       vsIxed = zip [0..] vs

instance SemiInner ℝ where
  dualBasisCandidates = fmap ((`Node`[]) . second recip)
                . sortBy (comparing $ negate . abs . snd)
                . filter ((/=0) . snd)

instance (Fractional'' s, Ord s, SemiInner s) => SemiInner (V1 s) where
  dualBasisCandidates = fmap ((`Node`[]) . second recip)
                . sortBy (comparing $ negate . abs . snd)
                . filter ((/=0) . snd)

#define FreeSemiInner(V, sabs) \
instance SemiInner (V) where {  \
  dualBasisCandidates            \
     = cartesianDualBasisCandidates Mat.basis (fmap sabs . toList) }
FreeSemiInner(V2 ℝ, abs)
FreeSemiInner(V3 ℝ, abs)
FreeSemiInner(V4 ℝ, abs)

instance ∀ u v . ( SemiInner u, SemiInner v, Scalar u ~ Scalar v ) => SemiInner (u,v) where
  dualBasisCandidates = fmap (\(i,(u,v))->((i,u),(i,v))) >>> unzip
              >>> dualBasisCandidates *** dualBasisCandidates
              >>> combineBaseis False mempty
   where combineBaseis :: Bool -> Set Int
                 -> ( Forest (Int, DualVector u)
                    , Forest (Int, DualVector v) )
                   -> Forest (Int, (DualVector u, DualVector v))
         combineBaseis _ _ ([], []) = []
         combineBaseis False forbidden (Node (i,du) bu' : abu, bv)
            | i`Set.member`forbidden  = combineBaseis False forbidden (abu, bv)
            | otherwise
                 = Node (i, (du, zeroV))
                        (combineBaseis True (Set.insert i forbidden) (bu', bv))
                       : combineBaseis False forbidden (abu, bv)
         combineBaseis True forbidden (bu, Node (i,dv) bv' : abv)
            | i`Set.member`forbidden  = combineBaseis True forbidden (bu, abv)
            | otherwise
                 = Node (i, (zeroV, dv))
                        (combineBaseis False (Set.insert i forbidden) (bu, bv'))
                       : combineBaseis True forbidden (bu, abv)
         combineBaseis _ forbidden (bu, []) = combineBaseis False forbidden (bu,[])
         combineBaseis _ forbidden ([], bv) = combineBaseis True forbidden ([],bv)
  
(^/^) :: (InnerSpace v, Eq (Scalar v), Fractional (Scalar v)) => v -> v -> Scalar v
v^/^w = case (v<.>w) of
   0 -> 0
   vw -> vw / (w<.>w)

class (LSpace v, LSpace (Scalar v)) => FiniteDimensional v where
  -- | Whereas 'Basis'-values refer to a single basis vector, a single
  --   'EntireBasis' value represents a complete collection of such basis vectors,
  --   which can be used to associate a vector with a list of coefficients.
  -- 
  --   For spaces with a canonical finite basis, 'EntireBasis' does not actually
  --   need to contain any information, since all vectors will anyway be represented in
  --   that same basis.
  data EntireBasis v :: *
  
  -- | Split up a linear map in “column vectors” WRT some suitable basis.
  decomposeLinMap :: (v+>w) -> (EntireBasis v, [w]->[w])
  
  -- | Assemble a vector from coefficients in some basis. Return any excess coefficients.
  recomposeEntire :: EntireBasis v -> [Scalar v] -> (v, [Scalar v])
  
  -- | Given a function that interprets a coefficient-container as a vector representation,
  --   build a linear function mapping to that space.
  recomposeContraLinMap :: (LinearSpace w, Scalar w ~ Scalar v, Hask.Functor f)
           => (f (Scalar w) -> w) -> f (DualVector v) -> v+>w
  
  -- | The existance of a finite basis gives us an isomorphism between a space
  --   and its dual space. Note that this isomorphism is not natural (i.e. it
  --   depends on the actual choice of basis, unlike everything else in this
  --   library).
  uncanonicallyFromDual :: DualVector v -+> v
  uncanonicallyToDual :: v -+> DualVector v
  


instance (Num''' s) => FiniteDimensional (ZeroDim s) where
  data EntireBasis (ZeroDim s) = ZeroBasis
  recomposeEntire ZeroBasis l = (Origin, l)
  decomposeLinMap _ = (ZeroBasis, id)
  recomposeContraLinMap _ _ = LinearMap Origin
  uncanonicallyFromDual = id
  uncanonicallyToDual = id
  
instance (Num''' s, LinearSpace s) => FiniteDimensional (V0 s) where
  data EntireBasis (V0 s) = V0Basis
  recomposeEntire V0Basis l = (V0, l)
  decomposeLinMap _ = (V0Basis, id)
  recomposeContraLinMap _ _ = LinearMap V0
  uncanonicallyFromDual = id
  uncanonicallyToDual = id
  
instance FiniteDimensional ℝ where
  data EntireBasis ℝ = RealsBasis
  recomposeEntire RealsBasis [] = (0, [])
  recomposeEntire RealsBasis (μ:cs) = (μ, cs)
  decomposeLinMap (LinearMap v) = (RealsBasis, (v:))
  recomposeContraLinMap fw = LinearMap . fw
  uncanonicallyFromDual = id
  uncanonicallyToDual = id

#define FreeFiniteDimensional(V, VB, take, give)        \
instance (Num''' s, LSpace s)                            \
            => FiniteDimensional (V s) where {            \
  data EntireBasis (V s) = VB;                             \
  uncanonicallyFromDual = id;                               \
  uncanonicallyToDual = id;                                  \
  recomposeEntire _ (take:cs) = (give, cs);                   \
  recomposeEntire b cs = recomposeEntire b $ cs ++ [0];        \
  decomposeLinMap (LinearMap m) = (VB, (toList m ++));          \
  recomposeContraLinMap fw mv = LinearMap $ (\v -> fw $ fmap (<.>^v) mv) <$> Mat.identity }
FreeFiniteDimensional(V1, V1Basis, c₀         , V1 c₀         )
FreeFiniteDimensional(V2, V2Basis, c₀:c₁      , V2 c₀ c₁      )
FreeFiniteDimensional(V3, V3Basis, c₀:c₁:c₂   , V3 c₀ c₁ c₂   )
FreeFiniteDimensional(V4, V4Basis, c₀:c₁:c₂:c₃, V4 c₀ c₁ c₂ c₃)
                                  
deriving instance Show (EntireBasis ℝ)
  
instance ( FiniteDimensional u, LinearSpace (DualVector u), DualVector (DualVector u) ~ u
         , FiniteDimensional v, LinearSpace (DualVector v), DualVector (DualVector v) ~ v
         , Scalar u ~ Scalar v, Fractional' (Scalar v) )
            => FiniteDimensional (u,v) where
  data EntireBasis (u,v) = TupleBasis !(EntireBasis u) !(EntireBasis v)
  decomposeLinMap (LinearMap (fu, fv))
       = case (decomposeLinMap (asLinearMap$fu), decomposeLinMap (asLinearMap$fv)) of
         ((bu, du), (bv, dv)) -> (TupleBasis bu bv, du . dv)
  recomposeEntire (TupleBasis bu bv) coefs = case recomposeEntire bu coefs of
                        (u, coefs') -> case recomposeEntire bv coefs' of
                         (v, coefs'') -> ((u,v), coefs'')
  recomposeContraLinMap fw dds
         = recomposeContraLinMap fw (fst<$>dds)
          ⊕ recomposeContraLinMap fw (snd<$>dds)
  uncanonicallyFromDual = uncanonicallyFromDual *** uncanonicallyFromDual
  uncanonicallyToDual = uncanonicallyToDual *** uncanonicallyToDual
  
deriving instance (Show (EntireBasis u), Show (EntireBasis v))
                    => Show (EntireBasis (u,v))

infixr 0 \$

-- | Inverse function application, in the sense of providing a
--   /least-squares-error/ solution to a linear equation system.
-- 
--   If you want to solve for multiple RHS vectors, be sure to partially
--   apply this operator to the matrix element.
(\$) :: ( FiniteDimensional u, FiniteDimensional v, SemiInner v
        , Scalar u ~ Scalar v, Fractional' (Scalar v) )
          => (u+>v) -> v -> u
(\$) m = fst . \v -> recomposeEntire mbas [v'<.>^v | v' <- v's]
 where v's = dualBasis $ mdecomp []
       (mbas, mdecomp) = decomposeLinMap m
    

pseudoInverse :: ( FiniteDimensional u, FiniteDimensional v, SemiInner v
                 , Scalar u ~ Scalar v, Fractional' (Scalar v) )
          => (u+>v) -> v+>u
pseudoInverse m = recomposeContraLinMap (fst . recomposeEntire mbas) v's
 where v's = dualBasis $ mdecomp []
       (mbas, mdecomp) = decomposeLinMap m


-- | The <https://en.wikipedia.org/wiki/Riesz_representation_theorem Riesz representation theorem>
--   provides an isomorphism between a Hilbert space and its (continuous) dual space.
riesz :: (FiniteDimensional v, InnerSpace v) => DualVector v -+> v
riesz = LinearFunction $ \dv ->
       let (bas, compos) = decomposeLinMap $ sampleLinearFunction $ applyDualVector $ dv
       in fst . recomposeEntire bas $ compos []

sRiesz :: (FiniteDimensional v, InnerSpace v) => DualSpace v -+> v
sRiesz = LinearFunction $ \dv ->
       let (bas, compos) = decomposeLinMap $ dv
       in fst . recomposeEntire bas $ compos []

coRiesz :: (LSpace v, Num''' (Scalar v), InnerSpace v) => v -+> DualVector v
coRiesz = fromFlatTensor . arr asTensor . sampleLinearFunction . inner

-- | Functions are generally a pain to display, but since linear functionals
--   in a Hilbert space can be represented by /vectors/ in that space,
--   this can be used for implementing a 'Show' instance.
showsPrecAsRiesz :: ( FiniteDimensional v, InnerSpace v, Show v
                    , HasBasis (Scalar v), Basis (Scalar v) ~ () )
                      => Int -> DualSpace v -> ShowS
showsPrecAsRiesz p dv = showParen (p>0) $ ("().<"++)
            . showsPrec 7 (sRiesz$dv)

instance Show (LinearMap ℝ (V0 ℝ) ℝ) where showsPrec = showsPrecAsRiesz
instance Show (LinearMap ℝ (V1 ℝ) ℝ) where showsPrec = showsPrecAsRiesz
instance Show (LinearMap ℝ (V2 ℝ) ℝ) where showsPrec = showsPrecAsRiesz
instance Show (LinearMap ℝ (V3 ℝ) ℝ) where showsPrec = showsPrecAsRiesz
instance Show (LinearMap ℝ (V4 ℝ) ℝ) where showsPrec = showsPrecAsRiesz


infixl 7 .<

-- | Outer product of a general @v@-vector and a basis element from @w@.
--   Note that this operation is in general pretty inefficient; it is
--   provided mostly to lay out matrix definitions neatly.
(.<) :: ( FiniteDimensional v, Num''' (Scalar v)
        , InnerSpace v, LSpace w, HasBasis w, Scalar v ~ Scalar w )
           => Basis w -> v -> v+>w
bw .< v = sampleLinearFunction $ LinearFunction $ \v' -> recompose [(bw, v<.>v')]

instance Show (LinearMap s v (V0 s)) where
  show _ = "zeroV"
instance (FiniteDimensional v, InnerSpace v, Scalar v ~ ℝ, Show v)
              => Show (LinearMap ℝ v (V1 ℝ)) where
  showsPrec p m = showParen (p>6) $ ("ex .< "++)
                       . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._x)) $ m)
instance (FiniteDimensional v, InnerSpace v, Scalar v ~ ℝ, Show v)
              => Show (LinearMap ℝ v (V2 ℝ)) where
  showsPrec p m = showParen (p>6)
              $ ("ex.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._x)) $ m)
         . (" ^+^ ey.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._y)) $ m)
instance (FiniteDimensional v, InnerSpace v, Scalar v ~ ℝ, Show v)
              => Show (LinearMap ℝ v (V3 ℝ)) where
  showsPrec p m = showParen (p>6)
              $ ("ex.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._x)) $ m)
         . (" ^+^ ey.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._y)) $ m)
         . (" ^+^ ez.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._z)) $ m)
instance (FiniteDimensional v, InnerSpace v, Scalar v ~ ℝ, Show v)
              => Show (LinearMap ℝ v (V4 ℝ)) where
  showsPrec p m = showParen (p>6)
              $ ("ex.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._x)) $ m)
         . (" ^+^ ey.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._y)) $ m)
         . (" ^+^ ez.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._z)) $ m)
         . (" ^+^ ew.<"++) . showsPrec 7 (sRiesz $ fmap (LinearFunction (^._w)) $ m)


-- $metricIntro
-- A norm is a way to quantify the magnitude of different vectors,
-- even if they point in different directions.
-- 
-- In an 'InnerSpace', a norm is always given by the scalar product,
-- but there are spaces without a canonical scalar product (or situations
-- in which this scalar product does not give the metric you want). Hence,
-- we let the functions like 'constructEigenSystem', which depend on a norm
-- for orthonormalisation, accept a 'Norm' as an extra argument instead of
-- requiring 'InnerSpace'.

-- | A norm defined by
-- 
-- @
-- ‖v‖ = √(∑ᵢ ⟨dᵢ|v⟩²)
-- @
-- 
-- for some dual vectors @dᵢ@. Note that this only really generates a norm/metric if
-- these form a complete basis of the dual space, otherwise it will merely be
-- a /seminorm/.
-- 
-- If the @dᵢ@ are an orthonormal system, you get the 'euclideanNorm' (in
-- an inefficient form).
spanNorm :: LSpace v => [DualVector v] -> Norm v
spanNorm dvs = Norm . LinearFunction $ \v -> sumV [dv ^* (dv<.>^v) | dv <- dvs]

spanVariance :: LSpace v => [v] -> Variance v
spanVariance = spanNorm

-- | A positive definite symmetric bilinear form.
newtype Norm v = Norm {
    applyNorm :: v -+> DualVector v
  }

type Variance v = Norm (DualVector v)

-- | The canonical standard metric on inner-product / Hilbert spaces.
euclideanNorm :: (LSpace v, InnerSpace v, DualVector v ~ v) => Norm v
euclideanNorm = Norm id

-- | The norm induced from the (arbirtrary) choice of basis in a finite space.
--   Only use this in contexts where you merely need /some/ norm, but don't
--   care if it might be biased in some unnatural way.
adhocNorm :: FiniteDimensional v => Norm v
adhocNorm = Norm uncanonicallyToDual

infixl 6 ^%
(^%) :: (LSpace v, Floating (Scalar v)) => v -> Norm v -> v
v ^% Norm m = v ^/ sqrt ((m$v)<.>^v)


infixr 0 <$|, |$|
-- | “Partially apply” a norm, yielding a dual vector
--   (i.e. a linear form that accepts the second argument of the scalar product).
-- 
-- @
-- (euclideanNorm '<$|' v) '<.>^' w  ≡  v '<.>' w
-- @
(<$|) :: LSpace v => Norm v -> v -> DualVector v
Norm m <$| v = m $ v

-- | The squared norm. More efficient than '|$|' because that needs to take
--   the square root.
normSq :: LSpace v => Norm v -> v -> Scalar v
normSq (Norm m) v = (m$v)<.>^v

-- | Use a 'Norm' to measure the length / norm of a vector.
-- 
-- @
-- euclideanNorm |$| v  ≡  √(v '<.>' v)
-- @
(|$|) :: (LSpace v, Floating (Scalar v)) => Norm v -> v -> Scalar v
(|$|) m = sqrt . normSq m

-- | `spanNorm` / `spanVariance` are inefficient if the number of vectors
--   is similar to the dimension of the space. Use this function to optimise
--   the underlying operator to a dense matrix representation.
densifyNorm :: LSpace v => Norm v -> Norm v
densifyNorm (Norm m) = Norm . arr $ sampleLinearFunction $ m

data OrthonormalSystem v = OrthonormalSystem {
      orthonormalityNorm :: Norm v
    , orthonormalVectors :: [v]
    }

orthonormaliseFussily :: (LSpace v, RealFloat (Scalar v))
                           => Norm v -> [v] -> [v]
orthonormaliseFussily me = go []
 where go _ [] = []
       go ws (v₀:vs)
         | mvd > 1/4  = let v = vd^/sqrt mvd
                        in v : go (v:ws) vs
         | otherwise  = go ws vs
        where vd = orthogonalComplementProj me ws $ v₀
              mvd = normSq me vd

orthogonalComplementProj :: LSpace v => Norm v -> [v] -> (v-+>v)
orthogonalComplementProj (Norm m) ws = LinearFunction $ \v₀
             -> foldl' (\v w -> v ^-^ w^*((m$v)<.>^w)) v₀ ws



data Eigenvector v = Eigenvector {
      ev_Eigenvalue :: Scalar v -- ^ The estimated eigenvalue @λ@.
    , ev_Eigenvector :: v       -- ^ Normalised vector @v@ that gets mapped to a multiple, namely:
    , ev_FunctionApplied :: v   -- ^ @f $ v ≡ λ *^ v @.
    , ev_Deviation :: v         -- ^ Deviation of these two supposedly equivalent expressions.
    , ev_Badness :: Scalar v    -- ^ Squared norm of the deviation, normalised by the eigenvalue.
    }
deriving instance (Show v, Show (Scalar v)) => Show (Eigenvector v)

-- | Lazily compute the eigenbasis of a linear map. The algorithm is essentially
--   a hybrid of Lanczos/Arnoldi style Krylov-spanning and QR-diagonalisation,
--   but we don't separate these steps but /interleave/ them at each operation.
--   The size of the eigen-subbasis increases with each step until the space's
--   dimesion is reached. (But the algorithm can also be used for
--   infinite-dimensional spaces.)
constructEigenSystem :: (LSpace v, RealFloat (Scalar v))
      => Norm v           -- ^ The notion of orthonormality.
      -> Scalar v           -- ^ Error bound for deviations from eigen-ness.
      -> (v-+>v)            -- ^ Operator to calculate the eigensystem of.
                            --   Must be Hermitian WRT the scalar product
                            --   defined by the given metric.
      -> [v]                -- ^ Starting vector(s) for the power method.
      -> [[Eigenvector v]]  -- ^ Infinite sequence of ever more accurate approximations
                            --   to the eigensystem of the operator.
constructEigenSystem me@(Norm m) ε₀ f = iterate (
                                             sortBy (comparing $
                                               negate . abs . ev_Eigenvalue)
                                           . map asEV
                                           . orthonormaliseFussily (Norm m)
                                           . newSys)
                                         . map (asEV . (^%me))
 where newSys [] = []
       newSys (Eigenvector λ v fv dv ε : evs)
         | ε>ε₀       = case newSys evs of
                         []     -> [fv^/λ, dv^*(sqrt $ λ^2/ε)]
                         vn:vns -> fv^/λ : vn : dv^*(sqrt $ λ^2/ε) : vns
         | ε>=0       = v : newSys evs
         | otherwise  = newSys evs
       asEV v = Eigenvector λ v fv dv ε
        where λ = v'<.>^fv
              ε = normSq me dv / (λ^2 + ε₀)
              fv = f $ v
              dv = v^*λ ^-^ fv
              v' = m $ v



-- | Find a system of vectors that approximate the eigensytem, in the sense that:
--   each true eigenvalue is represented by an approximate one, and that is closer
--   to the true value than all the other approximate EVs.
-- 
--   This function does not make any guarantees as to how well a single eigenvalue
--   is approximated, though.
roughEigenSystem :: (FiniteDimensional v, IEEE (Scalar v))
        => Norm v
        -> (v+>v)
        -> [Eigenvector v]
roughEigenSystem me f = go fBas 0 [[]]
 where go [] _ (_:evs:_) = evs
       go [] _ (evs:_) = evs
       go (v:vs) oldDim (evs:evss)
         | normSq me vPerp > fpε  = case evss of
             evs':_ | length evs' > oldDim
               -> go (v:vs) (length evs) evss
             _ -> let evss' = constructEigenSystem me fpε (arr f)
                                $ map ev_Eigenvector (head $ evss++[evs]) ++ [vPerp]
                  in go vs (length evs) evss'
         | otherwise              = go vs oldDim (evs:evss)
        where vPerp = orthogonalComplementProj me (ev_Eigenvector<$>evs) $ v
       fBas = (^%me) <$> snd (decomposeLinMap id) []
       fpε = epsilon * 8


orthonormalityError :: LSpace v => Norm v -> [v] -> Scalar v
orthonormalityError me vs = normSq me $ orthogonalComplementProj me vs $ sumV vs


normSpanningSystem :: (FiniteDimensional v, IEEE (Scalar v))
               => Norm v -> [DualVector v]
normSpanningSystem me@(Norm m) = scaleup <$> roughEigenSystem adhocNorm m'
 where m' = sampleLinearFunction $ uncanonicallyFromDual . m
       scaleup (Eigenvector λ _ fv _ _)
         | λ>0       = uncanonicallyToDual $ fv^/sqrt λ
       



(^) :: Num a => a -> Int -> a
(^) = (Hask.^)

