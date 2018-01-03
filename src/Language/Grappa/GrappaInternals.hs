{-# LANGUAGE TypeFamilies, GADTs, EmptyDataDecls, RankNTypes, EmptyCase #-}
{-# LANGUAGE DataKinds, ConstraintKinds, PolyKinds #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE TypeOperators, UndecidableInstances, ScopedTypeVariables #-}
{-# LANGUAGE FunctionalDependencies, DeriveFunctor, StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

module Language.Grappa.GrappaInternals where

import Data.Typeable
import Data.Functor.Const
import Data.Proxy (Proxy(..))
import GHC.Exts (Constraint, IsList(..))

import Language.Grappa.Distribution
import Language.Grappa.Model


--
-- * Representing Grappa Types
--

-- | The Grappa type of distributions. How it is represented depends on the
-- interpretation being used, so we do not instantiate it to an actual Haskell
-- type.
data Dist' a deriving Typeable

-- | Is a type considered to be a base type in Grappa?
type family IsBaseType a where
  IsBaseType (a -> b) = 'False
  IsBaseType (ADT a) = 'False
  IsBaseType (Dist' a) = 'False
  IsBaseType a = 'True

-- | An object-level representation of lists of Grappa types
data GrappaTypeListRepr (as :: [*]) where
  GrappaTypeListNil :: GrappaTypeListRepr '[]
  GrappaTypeListCons :: GrappaTypeRepr a -> GrappaTypeListRepr as ->
                        GrappaTypeListRepr (a ': as)

-- | An object-level representation of an application of a type constructor to 0
-- or more Grappa types
data GrappaTypeAppRepr (a :: k) where
  GrappaTypeAppBase :: Typeable a => GrappaTypeAppRepr a
  GrappaTypeAppApply :: GrappaTypeAppRepr (f :: * -> k) ->
                        GrappaTypeRepr a ->
                        GrappaTypeAppRepr (f a)

-- | An object-level representation of Grappa types
data GrappaTypeRepr (a :: *) where
  GrappaBaseType :: (IsAtomic a ~ 'True, IsBaseType a ~ 'True) =>
                    GrappaTypeAppRepr a -> GrappaTypeRepr a
  -- ^ A "base type" imported directly from Haskell, applied to 0 or more Grappa
  -- types; it must not be equal to any other Grappa type construct
  GrappaADTType :: GrappaADT adt => GrappaTypeAppRepr adt ->
                   GrappaTypeRepr (ADT adt)
  -- ^ A Grappa ADT type
  GrappaTupleType ::
    GrappaADT (TupleF as) =>
    GrappaTypeListRepr as -> GrappaTypeRepr (ADT (TupleF as))
  -- ^ A Grappa tuple type; note that we require 'GrappaADT', since the
  -- instance for 'TupleF' requires a class instance of 'GrappaTypeList' for
  -- @as@, not just a 'GrappaTypeListRepr'
  GrappaDistType :: GrappaTypeRepr a -> GrappaTypeRepr (Dist' a)
  -- ^ A Grappa distribution type
  GrappaArrowType :: GrappaTypeRepr a -> GrappaTypeRepr b ->
                     GrappaTypeRepr (a -> b)
  -- ^ A Grappa function type

instance Show (GrappaTypeRepr a) where
  show _ = "(FIXME HERE: write a Show instance for GrappaTypeRepr!)"

-- | A typeclass indicating that a type is a valid Grappa type
class GrappaType a where
  grappaTypeRepr :: GrappaTypeRepr a

-- | A typeclass indicating that a list of types are all valid Grappa types. We
-- represent it as a type family as well as a type constraint, below, as the
-- type family helps GHC pull out all the 'GrappaType' instances for each elem
type family GrappaTypeListFam (as :: [*]) :: Constraint where
  GrappaTypeListFam '[] = ()
  -- To help GHC not have to unroll as many type applications, we put some
  -- helper cases to skip forward multiple types in a type list
  GrappaTypeListFam (a ': '[]) = GrappaType a
  GrappaTypeListFam (a ': b ': '[]) = (GrappaType a, GrappaType b)
  GrappaTypeListFam (a ': b ': c ': '[]) =
    (GrappaType a, GrappaType b, GrappaType c)
  GrappaTypeListFam (a ': b ': c ': d ': '[]) =
    (GrappaType a, GrappaType b, GrappaType c, GrappaType d)
  GrappaTypeListFam (a ': b ': c ': d ': e ': rest) =
    (GrappaType a, GrappaType b, GrappaType c, GrappaType d,
     GrappaType e, GrappaTypeList rest)

class (IsTypeList as, GrappaTypeListFam as) => GrappaTypeList as where
  grappaTypeListRepr :: GrappaTypeListRepr as

-- Instances for lists of types
instance GrappaTypeList '[] where
  grappaTypeListRepr = GrappaTypeListNil
instance GrappaType a => GrappaTypeList '[a] where
  grappaTypeListRepr = GrappaTypeListCons grappaTypeRepr GrappaTypeListNil
instance (GrappaType a, GrappaType b) => GrappaTypeList '[a,b] where
  grappaTypeListRepr =
    GrappaTypeListCons grappaTypeRepr
    (GrappaTypeListCons grappaTypeRepr GrappaTypeListNil)
instance (GrappaType a, GrappaType b, GrappaType c) =>
         GrappaTypeList '[a,b,c] where
  grappaTypeListRepr =
    GrappaTypeListCons grappaTypeRepr
    (GrappaTypeListCons grappaTypeRepr
     (GrappaTypeListCons grappaTypeRepr GrappaTypeListNil))
instance (GrappaType a, GrappaType b, GrappaType c, GrappaType d) =>
         GrappaTypeList '[a,b,c,d] where
  grappaTypeListRepr =
    GrappaTypeListCons grappaTypeRepr
    (GrappaTypeListCons grappaTypeRepr
     (GrappaTypeListCons grappaTypeRepr
      (GrappaTypeListCons grappaTypeRepr GrappaTypeListNil)))
instance (GrappaType a, GrappaType b, GrappaType c,
          GrappaType d, GrappaType e, GrappaTypeList rest) =>
         GrappaTypeList (a ': b ': c ': d ': e ': rest) where
  grappaTypeListRepr =
    GrappaTypeListCons grappaTypeRepr
    (GrappaTypeListCons grappaTypeRepr
     (GrappaTypeListCons grappaTypeRepr
      (GrappaTypeListCons grappaTypeRepr
       (GrappaTypeListCons grappaTypeRepr grappaTypeListRepr))))

-- Instances for representing the core Grappa type constructs
instance GrappaTypeList as => GrappaType (ADT (TupleF as)) where
  grappaTypeRepr = GrappaTupleType grappaTypeListRepr
instance GrappaType a => GrappaType (Dist' a) where
  grappaTypeRepr = GrappaDistType grappaTypeRepr
instance (GrappaType a, GrappaType b) => GrappaType (a -> b) where
  grappaTypeRepr = GrappaArrowType grappaTypeRepr grappaTypeRepr

-- Instances for representing base types; remember to add more instances here
-- when we want to support more Haskell types in Grappa!
instance GrappaType Bool where
  grappaTypeRepr = GrappaBaseType GrappaTypeAppBase
instance GrappaType Int where
  grappaTypeRepr = GrappaBaseType GrappaTypeAppBase
instance GrappaType R where
  grappaTypeRepr = GrappaBaseType GrappaTypeAppBase
instance GrappaType Prob where
  grappaTypeRepr = GrappaBaseType GrappaTypeAppBase

-- | Test if a 'GrappaTypeRepr' is equal to 'R'
matchGrappaRType :: GrappaTypeRepr a -> Maybe (a :~: R)
matchGrappaRType (GrappaBaseType GrappaTypeAppBase) = eqT
matchGrappaRType _ = Nothing

-- | Test if a 'GrappaTypeRepr' is equal to 'Int'
matchGrappaIntType :: GrappaTypeRepr a -> Maybe (a :~: Int)
matchGrappaIntType (GrappaBaseType GrappaTypeAppBase) = eqT
matchGrappaIntType _ = Nothing


--
-- * Grappa ADTs
--

-- | Helper type: the identity
newtype Id a = Id {unId :: a} deriving (Functor, Show, Num, Floating, Fractional)

instance Applicative Id where
  pure = Id
  f <*> x = Id $ unId f $ unId x


-- FIXME: This approach to modeling ADTs does not let the type arguments change
-- in recursive uses of the ADT

-- | Builds an ADT type from an ADT type name
newtype ADT (adt :: (* -> *) -> * -> *) =
  ADT { unADT :: adt Id (ADT adt) }

-- | Class for mapping functions over ADTs
class TraversableADT (adt :: (* -> *) -> * -> *) where
  traverseADT :: Applicative m => (forall a. f a -> m (g a)) ->
                 adt f r -> m (adt g r)

-- | Map a function over an 'ADT'
mapADT :: TraversableADT adt => (forall a. f a -> g a) -> adt f r -> adt g r
mapADT f = unId . traverseADT (Id . f)

-- | Fold a function over all the constructor arguments of an ADT. Note that
-- this is /not/ the same as, say, a list fold, since here the "rest" argument
-- in a list is treated as a single argument, i.e., we do not recurse.
foldADT :: TraversableADT adt =>
           (forall a. f a -> r) -> (r -> r -> r) -> r -> adt f (ADT adt) -> r
foldADT resF f x = foldr f x . ctorArgsADT resF

-- | Typeclass of ADTs where we can enumerate all the constructors, by building
-- a list of ADT elements with 'Proxy's as arguments
class ReifyCtorsADT adt where
  reifyCtorsADT :: [adt Proxy (ADT adt)]

-- | Convert all the arguments of the constructor of an ADT into a list
ctorArgsADT :: TraversableADT adt => (forall a. f a -> r) ->
               adt f (ADT adt) -> [r]
ctorArgsADT resF = getConst . traverseADT (Const . (: []) . resF)

-- | Class for "valid" Grappa ADT types
class (TraversableADT adt, ReifyCtorsADT adt) =>
      GrappaADT (adt :: (* -> *) -> * -> *) where
  -- | Stronger form of 'TraversableADT', where we know that the argument types
  -- are themselves valid Grappa types
  gtraverseADT :: Applicative m =>
                  (forall a. GrappaType a => f a -> m (g a)) ->
                  adt f (ADT adt) -> m (adt g (ADT adt))

-- | Map a function on well-typed objects over an 'ADT'
gmapADT :: GrappaADT adt => (forall a. GrappaType a => f a -> g a) ->
           adt f (ADT adt) -> adt g (ADT adt)
gmapADT f = unId . gtraverseADT (Id . f)

-- | Helper type class for 'Show'ing 'ADT's
class ShowADT (adt :: (* -> *) -> * -> *) where
  showADT :: ADT adt -> String

instance ShowADT adt => Show (ADT adt) where
  show = showADT

-- NOTE: we don't want the generalized Show instance for an ADT, but usually
-- want adt-specific printing...
--
-- deriving instance (Show (adt f (ADT adt f))) => Show (ADT adt f)

--
-- * Grappa Distribution Variables
--

-- | A type is "atomic" iff it is not an 'ADT'
type family IsAtomic a :: Bool where
  IsAtomic (ADT g) = 'False
  IsAtomic a = 'True

-- | Variables that can be passed into a distribution, which are either "data"
-- variables, which have a value, or "parameter" variables, which do not. For
-- ADT types, "data" variables are actually constructors applied to variables of
-- their argument types.
data DistVar a where
  -- | A parameter variable, i.e., a variable without a value
  VParam :: DistVar a
  -- | A data variable, i.e., a variable with a value
  VData :: IsAtomic a ~ 'True => a -> DistVar a
  -- | An ADT variable, with a head constructor (in @adt@) and a sequence of
  -- variables for the arguments of that constructor
  VADT :: TraversableADT adt => adt DistVar (ADT adt) -> DistVar (ADT adt)

-- | Helper class for building 'EmbedDistVar' instances without overlapping
class EmbedDistVarH (b::Bool) a where
  embedDistVarH :: Proxy b -> a -> DistVar a

-- | Typeclass to embed data values into 'DistVar'. This is a sort of
-- well-formedness condition, saying that @a@ can be used with 'DistVar'.
class EmbedDistVarH (IsAtomic a) a => EmbedDistVar a where { }

instance EmbedDistVarH (IsAtomic a) a => EmbedDistVar a where { }

embedDistVar :: EmbedDistVar a => a -> DistVar a
embedDistVar (x::a) = embedDistVarH (undefined :: Proxy (IsAtomic a)) x

instance IsAtomic a ~ 'True => EmbedDistVarH 'True a where
  embedDistVarH _ = VData

-- | Helper class for embedding ADT values into 'DistVar'
class EmbedDistVarADT adt where
  embedDistVarADT :: adt Id (ADT adt) -> adt DistVar (ADT adt)

instance (EmbedDistVarADT adt, TraversableADT adt) =>
         EmbedDistVarH 'False (ADT adt) where
  embedDistVarH _ (ADT adt) = VADT $ embedDistVarADT adt

-- | Create a 'DistVar' from a value of any well-formedGrappa type
--
-- FIXME: it would be nice to use this instead of the above stuff...
typedEmbedDistVar :: GrappaType a => a -> DistVar a
typedEmbedDistVar x = helper grappaTypeRepr x where
  helper :: GrappaTypeRepr a -> a -> DistVar a
  helper (GrappaBaseType _) d = VData d
  helper (GrappaADTType _) (ADT adt) =
    VADT $ gmapADT (typedEmbedDistVar . unId) adt
  helper (GrappaTupleType _) (ADT adt) =
    VADT $ gmapADT (typedEmbedDistVar . unId) adt
  helper (GrappaDistType _) d = VData d
  helper (GrappaArrowType _ _) d = VData d

-- | Pattern-match a 'DistVar' at an 'ADT' type, returning either the "body" of
-- the ADT variable, in the case of the 'VADT' constructor, or a default case
-- for a parameter variable
matchADTDistVar :: adt DistVar (ADT adt) -> DistVar (ADT adt) ->
                   adt DistVar (ADT adt)
matchADTDistVar dflt VParam = dflt
matchADTDistVar _ (VADT adt) = adt

-- | Pattern-match a 'DistVar' at an atomic, i.e. non-'ADT', type against a
-- fixed value of that type, returning 'True' if that 'DistVar' is either
-- 'VData' of that fixed value or a 'VParam'
matchAtomicDistVar :: (Eq a, IsAtomic a ~ 'True) => a -> DistVar a -> Bool
matchAtomicDistVar _ VParam = True
matchAtomicDistVar a (VData x) = a == x

mapDistVar :: (IsAtomic a ~ 'True, IsAtomic b ~ 'True)
           => (a -> b) -> DistVar a -> DistVar b
mapDistVar _ VParam = VParam
mapDistVar f (VData x) = VData (f x)

--
-- * Grappa Distributions
--

type Dist c a = DistVar a -> Model c a

-- | Build a Grappa distribution from any Haskell distribution type whose
-- support type is atomic
atomicDist :: (c d, PDFDist d, IsAtomic (Support d) ~ 'True) =>
              d -> Dist c (Support d)
atomicDist d VParam = sample d
atomicDist d (VData x) = observe x d >> return x

-- | The 'Normal' distribution as a 'Model' combinator
normal :: c Normal => R -> R -> Dist c R
normal mu sigma = atomicDist (Normal mu sigma)

-- | The 'Uniform' distribution as a 'Model' combinator
uniform :: c Uniform => R -> R -> Dist c R
uniform low high = atomicDist (Uniform low high)

-- | The 'Cauchy' distribution
cauchy :: c Cauchy => Dist c R
cauchy = atomicDist Cauchy

-- | The 'Categorical' distribution
categorical :: c Categorical => GList Prob -> Dist c Int
categorical lst = atomicDist (Categorical (toList lst))

-- | The 'Dirichlet' distribution
dirichlet :: c Dirichlet => GList R -> Dist c (GList R)
dirichlet lst = error "dirichlet function not implemented!"

-- | The 'MVNormal' distribution as a 'Model' combinator; NOTE that the @c@
-- argument is a Cholesky decomposition of the standard covariance matrix used
-- with multivariate normals, but it is further non-standard in that it is an
-- upper-triangular, not lower-triangular, matrix. See the documentation for
-- 'MVNormal' for more details.
--
-- NOTE: We actually use the @matrix@ package instead of the @hmatrix@ package
-- here for matrices, so the vector and matrix types are not the same as those
-- used by 'MVNormal'... so this function is actually undefined, and we just use
-- the @Interp__@ method to define it for each interpretation.
mvNormal :: c MVNormal => RMatrix -> RMatrix -> Dist c RMatrix
mvNormal _ _ = error "mv_normal not defined!"

type ReprDist d f a = DistVar a -> ReprModel d f a

-- | Build a Grappa distribution from any Haskell distribution type whose
-- support type is atomic
atomicDistRepr :: (IsAtomic (ReprSupport d) ~ 'True, c d f) =>
              d f -> ReprDist c f (f (ReprSupport d))
atomicDistRepr d VParam = sampleRepr d
atomicDistRepr d (VData x) = observeRepr x d >> return x

-- | The 'Normal' distribution as a 'Model' combinator
normalRepr :: (c ReprNormal f) => f R -> f R -> ReprDist c f (f R)
normalRepr mu sigma = atomicDistRepr (ReprNormal mu sigma)

-- | The 'Uniform' distribution as a 'Model' combinator
uniformRepr :: (c ReprUniform f) => f R -> f R -> ReprDist c f (f R)
uniformRepr low high = atomicDistRepr (ReprUniform low high)

-- | The 'Cauchy' distribution
cauchyRepr :: (c ReprCauchy f) => ReprDist c f (f R)
cauchyRepr = atomicDistRepr ReprCauchy

-- | The 'Categorical' distribution
categoricalRepr :: (c ReprCategorical f) => GList (f Prob) -> ReprDist c f (f Int)
categoricalRepr lst = atomicDistRepr (ReprCategorical (toList lst))

-- | The 'MVNormal' distribution
mvNormalRepr :: (c ReprMVNormal f) => f RMatrix -> f RMatrix ->
                ReprDist c f (f RMatrix)
mvNormalRepr mu c = atomicDistRepr (ReprMVNormal mu c)


-- | A single case of a mixture model (FIXME HERE: document this!)
data MixtureCase c a
  = MixtureCase { mixCaseModel :: DistVar a -> Maybe (Model c a),
                  mixCaseWeight :: Prob }

-- | The trivial mixture distribution, for a single 'MixtureCase'
mixtureDist1 :: MixtureCase c a -> Dist c a
mixtureDist1 mcase var =
  case mixCaseModel mcase var of
    Just model -> model
    Nothing -> error "Singleton mixture distribution: no matching cases!"

-- | FIXME HERE: document this!
mixtureDist :: forall c a. c Categorical => [MixtureCase c a] -> Dist c a
mixtureDist mcases var =
  do
    -- First, build a list of (model, w) pairs of models whose patterns did match
    -- the variable, along with a list of weights of models that did not match
    let (models, other_ws) =
          foldr (\mcase (models',other_ws') ->
                  case mixCaseModel mcase var of
                    Just model ->
                      ((model, mixCaseWeight mcase):models', other_ws')
                    Nothing ->
                      (models', mixCaseWeight mcase:other_ws'))
          ([],[]) mcases

    -- Next, penalize the current computation using the wieghts of the models
    -- that matched vs those that didn't match
    case other_ws of
      [] ->
        -- If there were no non-matching models, this is a no-op
        return ()
      _ ->
        -- Otherwise, we model all the matching cases as choice 0, and condition
        -- on that choice vs all the weights of the non-matching cases
        observe 0 $ Categorical (sum (map snd models) : other_ws)

    -- Finally, choose a model and execute it
    case models of
      [] ->
        -- If no models are available, signal an error
        error "Mixture distribution: no matching cases!"
      [(model,_)] ->
        -- If only one model is available, choose it unconditionally
        model
      _ ->
        -- Otherwise, choose a model randomly
        do i <- sample $ Categorical $ map snd models
           fst (models!!i)


--
-- * Tuple ADTs
--

-- | A generic tuple type as an ADT
data TupleF (ts :: [*]) f (r :: *) where
  Tuple0 :: TupleF '[] f r
  -- | Note: one-tuples are needed for recursive 'TupleN' constructions
  Tuple1 :: f a -> TupleF '[a] f r
  Tuple2 :: f a -> f b -> TupleF '[a, b] f r
  Tuple3 :: f a -> f b -> f c -> TupleF '[a, b, c] f r
  Tuple4 :: f a -> f b -> f c -> f d -> TupleF '[a, b, c, d] f r
  TupleN :: f a -> f b -> f c -> f d -> f e -> TupleF rest f r ->
            TupleF (a ': b ': c ': d ': e ': rest) f r

-- | This says that @ts@ is a well-formed list of types, that we can reflect on
class IsTypeList ts where
  typeListProxy :: TupleF ts Proxy r

instance IsTypeList '[] where
  typeListProxy = Tuple0

instance IsTypeList '[a] where
  typeListProxy = Tuple1 Proxy

instance IsTypeList '[a, b] where
  typeListProxy = Tuple2 Proxy Proxy

instance IsTypeList '[a, b, c] where
  typeListProxy = Tuple3 Proxy Proxy Proxy

instance IsTypeList '[a, b, c, d] where
  typeListProxy = Tuple4 Proxy Proxy Proxy Proxy

instance IsTypeList rest => IsTypeList (a ': b ': c ': d ': e ': rest) where
  typeListProxy = TupleN Proxy Proxy Proxy Proxy Proxy typeListProxy

-- | "Proofs" that @t@ is in the list @ts@ of types
data TypeListElem ts t where
  TypeListElem_Base :: TypeListElem (t ': ts) t
  TypeListElem_Cons :: TypeListElem ts t -> TypeListElem (u ': ts) t

-- | Add an extra element to a tuple
tupleCons :: f t -> TupleF ts f r1 -> TupleF (t ': ts) f r2
tupleCons t Tuple0 = Tuple1 t
tupleCons t (Tuple1 a) = Tuple2 t a
tupleCons t (Tuple2 a b) = Tuple3 t a b
tupleCons t (Tuple3 a b c) = Tuple4 t a b c
tupleCons t (Tuple4 a b c d) = TupleN t a b c d Tuple0
tupleCons t (TupleN a b c d e rest) = TupleN t a b c d $ tupleCons e rest

-- | Get the first element of a tuple
tupleHead :: TupleF (t ': ts) f r -> f t
tupleHead (Tuple1 a) = a
tupleHead (Tuple2 a _) = a
tupleHead (Tuple3 a _ _) = a
tupleHead (Tuple4 a _ _ _) = a
tupleHead (TupleN a _ _ _ _ _) = a

-- | Remove the first element of a tuple
tupleTail :: TupleF (t ': ts) f r1 -> TupleF ts f r2
tupleTail (Tuple1 _) = Tuple0
tupleTail (Tuple2 _ b) = Tuple1 b
tupleTail (Tuple3 _ b c) = Tuple2 b c
tupleTail (Tuple4 _ b c d) = Tuple3 b c d
tupleTail (TupleN _ b c d e rest) =
  tupleCons b $ tupleCons c $ tupleCons d $ tupleCons e rest

-- | Project an element of a tuple
projectTuple :: TypeListElem ts t -> TupleF ts f r -> f t
projectTuple TypeListElem_Base tup = tupleHead tup
projectTuple (TypeListElem_Cons elemPf) tup =
  projectTuple elemPf $ tupleTail tup

-- Need a TraversableADT instance for each ADT type
instance TraversableADT (TupleF as) where
  traverseADT _ Tuple0 = pure Tuple0
  traverseADT f (Tuple1 a) = pure Tuple1 <*> f a
  traverseADT f (Tuple2 a b) = pure Tuple2 <*> f a <*> f b
  traverseADT f (Tuple3 a b c) = pure Tuple3 <*> f a <*> f b <*> f c
  traverseADT f (Tuple4 a b c d) = pure Tuple4 <*> f a <*> f b <*> f c <*> f d
  traverseADT f (TupleN a b c d e rest) =
    pure TupleN <*> f a <*> f b <*> f c <*> f d <*> f e <*> traverseADT f rest

untraverseTuple :: (Functor g, IsTypeList bs) =>
                   (forall a. g (f a) -> h a) ->
                   g (TupleF bs f r) -> TupleF bs h r
untraverseTuple = helper typeListProxy
  where
    helper :: Functor g => TupleF bs proxy r ->
              (forall a. g (f a) -> h a) -> g (TupleF bs f r) -> TupleF bs h r
    helper Tuple0 = \_ _ -> Tuple0
    helper tup@(Tuple1 _) = helperStep tup
    helper tup@(Tuple2 _ _) = helperStep tup
    helper tup@(Tuple3 _ _ _) = helperStep tup
    helper tup@(Tuple4 _ _ _ _) = helperStep tup
    helper tup@(TupleN _ _ _ _ _ _) = helperStep tup

    helperStep :: Functor g => TupleF (b ': bs) proxy r ->
                  (forall a. g (f a) -> h a) ->
                  g (TupleF (b ': bs) f r) -> TupleF (b ': bs) h r
    helperStep ts f gtup =
      tupleCons (f $ fmap tupleHead gtup)
      (helper (tupleTail ts) f $ fmap tupleTail gtup)

-- | Build a tuple from a polymorphic function for each element
buildTuple :: IsTypeList bs => (forall a. f a) -> TupleF bs f r
buildTuple f = untraverseTuple (\_ -> f) (Id typeListProxy)

-- Need a ReifyCtorsADT instance for each ADT type
instance IsTypeList ts => ReifyCtorsADT (TupleF ts) where
  reifyCtorsADT = [buildTuple Proxy]

-- | Map a binary function over tuples
mapTuple2 :: (forall a. f a -> g a -> h a) ->
             TupleF ts f r -> TupleF ts g r -> TupleF ts h r
mapTuple2 _ Tuple0 Tuple0 = Tuple0
mapTuple2 f (Tuple1 a1) (Tuple1 a2) = Tuple1 (f a1 a2)
mapTuple2 f (Tuple2 a1 b1) (Tuple2 a2 b2) = Tuple2 (f a1 a2) (f b1 b2)
mapTuple2 f (Tuple3 a1 b1 c1) (Tuple3 a2 b2 c2) =
  Tuple3 (f a1 a2) (f b1 b2) (f c1 c2)
mapTuple2 f (Tuple4 a1 b1 c1 d1) (Tuple4 a2 b2 c2 d2) =
  Tuple4 (f a1 a2) (f b1 b2) (f c1 c2) (f d1 d2)
mapTuple2 f (TupleN a1 b1 c1 d1 e1 rest1) (TupleN a2 b2 c2 d2 e2 rest2) =
  TupleN (f a1 a2) (f b1 b2) (f c1 c2) (f d1 d2) (f e1 e2) $
  mapTuple2 f rest1 rest2


-- Need a GrappaADT instance for each ADT type
instance GrappaTypeList as => GrappaADT (TupleF as) where
  gtraverseADT = helper where
    helper :: (GrappaTypeList bs, Applicative m) =>
              (forall a. GrappaType a => f a -> m (g a)) ->
              TupleF bs f r -> m (TupleF bs g r)
    helper _ Tuple0 = pure Tuple0
    helper f (Tuple1 a) = pure Tuple1 <*> f a
    helper f (Tuple2 a b) = pure Tuple2 <*> f a <*> f b
    helper f (Tuple3 a b c) = pure Tuple3 <*> f a <*> f b <*> f c
    helper f (Tuple4 a b c d) = pure Tuple4 <*> f a <*> f b <*> f c <*> f d
    helper f (TupleN a b c d e rest) =
      pure TupleN <*> f a <*> f b <*> f c <*> f d <*> f e <*> helper f rest

-- | Type synonym for Grappa tuples
type GTuple ts = ADT (TupleF ts)

-- | Defined type class for mappping a constraint function over a list; note
-- that we special-case small-sized lists, to help GHC do less unfolding
type family MapC (f :: * -> Constraint) (ts :: [*]) :: Constraint where
  MapC f '[] = ()
  MapC f '[a] = f a
  MapC f '[a,b] = (f a, f b)
  MapC f '[a,b,c] = (f a, f b, f c)
  MapC f '[a,b,c,d] = (f a, f b, f c, f d)
  MapC f (a ': b ': c ': d ': e ': rest) =
    (f a, f b, f c, f d, f e, MapC f rest)

instance MapC Show ts => ShowADT (TupleF ts) where
  showADT (ADT tup_body) = helper tup_body where
    helper :: forall ts' r. MapC Show ts' => TupleF ts' Id r -> String
    helper Tuple0 = "()"
    helper (Tuple1 (Id a)) = "(" ++ show a ++ ")"
    helper (Tuple2 (Id a) (Id b)) =
      "(" ++ show a ++ "," ++ show b ++ ")"
    helper (Tuple3 (Id a) (Id b) (Id c)) =
      "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ")"
    helper (Tuple4 (Id a) (Id b) (Id c) (Id d)) =
      "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ "," ++ show d ++ ")"
    helper (TupleN (Id a) (Id b) (Id c) (Id d) (Id e) rest) =
      "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ "," ++ show d
      ++ "," ++ show e ++ "," ++ helper rest ++ ")"

-- Also need an EmbedDistVarADT instance for each ADT type
instance MapC EmbedDistVar ts => EmbedDistVarADT (TupleF ts) where
  embedDistVarADT tup = helper tup where
    helper :: forall ts' r. MapC EmbedDistVar ts' =>
              TupleF ts' Id r -> TupleF ts' DistVar r
    helper Tuple0 = Tuple0
    helper (Tuple1 (Id a)) = Tuple1 (embedDistVar a)
    helper (Tuple2 (Id a) (Id b)) =
      Tuple2 (embedDistVar a) (embedDistVar b)
    helper (Tuple3 (Id a) (Id b) (Id c)) =
      Tuple3 (embedDistVar a) (embedDistVar b) (embedDistVar c)
    helper (Tuple4 (Id a) (Id b) (Id c) (Id d)) =
      Tuple4 (embedDistVar a) (embedDistVar b) (embedDistVar c) (embedDistVar d)
    helper (TupleN (Id a) (Id b) (Id c) (Id d) (Id e) rest) =
      TupleN (embedDistVar a) (embedDistVar b) (embedDistVar c) (embedDistVar d)
      (embedDistVar e) (helper rest)


--
-- * Boolean ADT
--

-- | The list type functor
data BoolF f r = TrueF | FalseF
  deriving (Eq, Show, Typeable)

-- Need a GrappaTypeRepr instance
instance GrappaType (ADT BoolF) where
  grappaTypeRepr = GrappaADTType GrappaTypeAppBase

-- Need a TraversableADT instance for each ADT type
instance TraversableADT BoolF where
  traverseADT _ TrueF  = pure TrueF
  traverseADT _ FalseF = pure FalseF

-- Need a ReifyCtorsADT instance for each ADT type
instance ReifyCtorsADT BoolF where
  reifyCtorsADT = [TrueF, FalseF]

-- Need a GrappaADT instance for each ADT type
instance GrappaADT BoolF where
  gtraverseADT _ TrueF  = pure TrueF
  gtraverseADT _ FalseF = pure FalseF

-- Also need an EmbedDistVarADT instance for each ADT type
instance EmbedDistVarADT BoolF where
  embedDistVarADT TrueF  = TrueF
  embedDistVarADT FalseF = FalseF

-- | Type synonym for lists, as Grappa ADTs
type GBool = ADT BoolF

fromHaskellBool :: Bool -> BoolF f r
fromHaskellBool True  = TrueF
fromHaskellBool False = FalseF

ifF :: BoolF f a -> t -> t -> t
ifF TrueF  t _ = t
ifF FalseF _ e = e

--
-- * List ADT
--

-- | The list type functor
data ListF a f r = Nil | Cons (f a) (f r)

-- Need a GrappaTypeRepr instance
instance GrappaType a => GrappaType (ADT (ListF a)) where
  grappaTypeRepr =
    GrappaADTType (GrappaTypeAppApply GrappaTypeAppBase grappaTypeRepr)

--deriving instance (Show (f a), Show (f r)) => Show (ListF a f r)

-- Need a TraversableADT instance for each ADT type
instance TraversableADT (ListF a) where
  traverseADT _ Nil = pure Nil
  traverseADT f (Cons x xs) = pure Cons <*> f x <*> f xs

-- Need a ReifyCtorsADT instance for each ADT type
instance ReifyCtorsADT (ListF a) where
  reifyCtorsADT = [Nil, Cons Proxy Proxy]

-- Need a GrappaADT instance for each ADT type
instance GrappaType a => GrappaADT (ListF a) where
  gtraverseADT _ Nil = pure Nil
  gtraverseADT f (Cons x xs) = pure Cons <*> f x <*> f xs

-- Also need an EmbedDistVarADT instance for each ADT type
instance EmbedDistVar a => EmbedDistVarADT (ListF a) where
  embedDistVarADT Nil = Nil
  embedDistVarADT (Cons (Id x) (Id (ADT xs))) =
    Cons (embedDistVar x) (VADT $ embedDistVarADT xs)

-- | Type synonym for lists, as Grappa ADTs
type GList a = ADT (ListF a)

adtDist__ListF :: c Categorical
              => Prob
              -> (DistVar (GTuple '[]) -> Model c (TupleF '[] f r1))
              -> Prob
              -> (DistVar (GTuple '[a, GList a]) -> Model c (TupleF '[a, GList a] f r2))
              -> DistVar (GList a)
              -> Model c (ListF a f (ADT (ListF a)))
adtDist__ListF pNil dNil pCons dCons VParam = do
  i <- sample $ Categorical [ pNil, pCons ]
  case i of
    0 -> do
      ret <- dCons (VADT (Tuple2 VParam VParam))
      case ret of
        Tuple2 x xs -> return (Cons x xs)
    1 -> do
      _ <- dNil (VADT (Tuple0))
      return Nil
    _ -> error "[unreachable]"
adtDist__ListF pNil dNil pCons _dCons (VADT Nil) = do
  observe 0 $ Categorical [ pNil, pCons ]
  _ <- dNil (VADT Tuple0)
  return Nil
adtDist__ListF pNil _dNil pCons dCons (VADT (Cons x xs)) = do
  observe 1 $ Categorical [ pNil, pCons ]
  ret <- dCons (VADT (Tuple2 x xs))
  case ret of
    Tuple2 y ys -> return (Cons y ys)

ctorDist__Nil :: ((DistVar (GTuple '[])) -> Model c (TupleF '[] f r1))
              -> DistVar (GList a) -> Model c (ListF a f (ADT (ListF a)))
ctorDist__Nil dNil VParam = do
  _ <- dNil (VADT (Tuple0))
  return Nil
ctorDist__Nil dNil (VADT Nil) = do
  _ <- dNil (VADT (Tuple0))
  return Nil
ctorDist__Nil _dNil (VADT (Cons _ _)) = do
  weight 0
  error "Violated model assumptions!"

ctorDist__Cons ::
  ((DistVar (GTuple '[a, GList a])) -> Model c (TupleF '[a, GList a] f r1)) ->
  DistVar (GList a) -> Model c (ListF a f (ADT (ListF a)))
ctorDist__Cons dCons VParam = do
  ret <- dCons (VADT (Tuple2 VParam VParam))
  case ret of
    Tuple2 y ys -> return (Cons y ys)
ctorDist__Cons dCons (VADT (Cons x xs)) = do
  ret <- dCons (VADT (Tuple2 x xs))
  case ret of
    Tuple2 y ys -> return (Cons y ys)
ctorDist__Cons _dCons (VADT Nil) = do
  weight 0
  error "Violated model assumptions!"

instance Show a => ShowADT (ListF a) where
  showADT = show . toList

-- | Map an operation over a 'DistVar' 'GList'
mapDV :: (DistVar a -> DistVar b) -> DistVar (GList a) -> DistVar (GList b)
mapDV _ VParam = VParam
mapDV _ (VADT Nil) = VADT Nil
mapDV f (VADT (Cons x xs)) =
  VADT (Cons (f x) (mapDV f xs))

-- | Zip two 'DistVar' 'GList' values together
zipDV :: DistVar (GList a) -> DistVar (GList b) -> DistVar (GList (GTuple [a, b]))
zipDV (VADT Nil) _ = VADT Nil
zipDV _ (VADT Nil) = VADT Nil
zipDV (VADT (Cons x xs)) (VADT (Cons y ys)) =
  VADT (Cons (VADT (Tuple2 x y)) (zipDV xs ys))
zipDV (VADT (Cons x xs)) VParam =
  VADT (Cons (VADT (Tuple2 x VParam)) (zipDV xs VParam))
zipDV VParam (VADT (Cons y ys)) =
  VADT (Cons (VADT (Tuple2 VParam y)) (zipDV VParam ys))
zipDV VParam VParam = VParam

listRepeatF :: a -> ADT (ListF a)
listRepeatF f = x
  where x = ADT (Cons (pure f) (pure x))

listIterateF :: a -> (a -> a) -> ADT (ListF a)
listIterateF x f = ADT (Cons (pure x) (pure (listIterateF (f x) f)))

enumFromByF :: (Num a) => a -> a -> ADT (ListF a)
enumFromByF from by = listIterateF from (+by)

enumFromToByF :: (Ord a, Num a) => a -> a -> a -> ADT (ListF a)
enumFromToByF from to by = go from
  where go n
          | n > to    = ADT Nil
          | otherwise = ADT (Cons (pure n) (pure (go (n + by))))

fromHaskellList :: [a] -> GList a
fromHaskellList = fromList

toHaskellList :: GList a -> [a]
toHaskellList = toList

-- | Convert a Grappa list with a non-'Id' functor to a Haskell list
toHaskellListF :: (f (ADT (ListF a)) -> ListF a f (ADT (ListF a))) ->
                  ListF a f (ADT (ListF a)) -> [f a]
toHaskellListF _ Nil = []
toHaskellListF unwrap (Cons x xs) = x : toHaskellListF unwrap (unwrap xs)

-- | Convert a Haskell list with a non-'Id' functor to a Grappa list
fromHaskellListF :: (ListF a f (ADT (ListF a)) -> f (ADT (ListF a))) ->
                    [f a] -> ListF a f (ADT (ListF a))
fromHaskellListF _ [] = Nil
fromHaskellListF wrap (x : xs) = Cons x (wrap $ fromHaskellListF wrap xs)

instance IsList (ADT (ListF a)) where
  type Item (ADT (ListF a)) = a
  fromList [] = ADT Nil
  fromList (x:xs) = ADT (Cons (Id x) (Id (fromList xs)))
  toList (ADT Nil) = []
  toList (ADT (Cons (Id x) (Id xs))) = x : toList xs


class GrappaShow t where
  grappaShow :: t -> String

instance GrappaShow Double where
  grappaShow = show

instance GrappaShow Int where
  grappaShow = show

instance GrappaShow a => GrappaShow (Id a) where
  grappaShow (Id x) = grappaShow x

type family MapF (f :: * -> *) (xs :: [*]) where
  MapF f '[] = '[]
  MapF f (x ': xs) = f x ': MapF f xs

instance MapC GrappaShow (MapF f ts) => GrappaShow (TupleF ts f r) where
  grappaShow Tuple0 = "()"
  grappaShow (Tuple1 a) = "(" ++ grappaShow a ++ ")"
  grappaShow (Tuple2 a b) = "(" ++ grappaShow a ++ "," ++ grappaShow b ++ ")"
  grappaShow (Tuple3 a b c) =
    "(" ++ grappaShow a ++ "," ++ grappaShow b ++ "," ++ grappaShow c ++ ")"
  grappaShow (Tuple4 a b c d) =
    "(" ++ grappaShow a ++ "," ++ grappaShow b ++ "," ++ grappaShow c ++
    "," ++ grappaShow d ++ ")"
  grappaShow (TupleN a b c d e _) =
    "(" ++ grappaShow a ++ "," ++ grappaShow b ++ "," ++ grappaShow c ++
    "," ++ grappaShow d ++ "," ++ grappaShow e ++ ", ...)"

instance (GrappaShow (f t), GrappaShowListContents (f r)) => GrappaShow (ListF t f r) where
  grappaShow Nil = "[]"
  grappaShow lst = "[" ++ go (showListContents lst) ++ "]"
    where go [] = ""
          go [x] = x
          go (x:xs) = x ++ "," ++ go xs

class GrappaShowListContents t where
  showListContents :: t -> [String]

instance (GrappaShow (f t), GrappaShowListContents (f r)) => GrappaShowListContents (ListF t f r) where
  showListContents Nil = []
  showListContents (Cons x xs) =
    grappaShow x : showListContents xs

instance GrappaShowListContents t => GrappaShowListContents (Id t) where
  showListContents (Id x) = showListContents x
