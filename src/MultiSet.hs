{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- An implementation of ordered multi sets -}
module MultiSet where

import qualified Data.Bifunctor as Bifunc
import Data.Function (on)
import Data.Maybe (fromJust, maybeToList)
import qualified FingerTree as Base
import qualified Set
import SetHelper
import Prelude hiding (map, null)

data MultiSizeMax a = MultiSizeMax
  { cardinality :: Size, -- sum of all multiplicities
    supportSize :: Size, -- number of unique elements
    getMax :: Max a
  }
  deriving (Eq, Show)

data MultiElem a = MultiElem
  { getMultiElem :: a,
    multiplicity :: Integer
  }
  deriving (Show)

newtype MultiSet a
  = MultiSet (Base.FingerTree (MultiSizeMax a) (MultiElem a))

instance Semigroup (MultiSizeMax a) where
  x <> y =
    MultiSizeMax
      { cardinality = cardinality x <> cardinality y,
        supportSize = supportSize x <> supportSize y,
        getMax = getMax x <> getMax y
      }

instance Monoid (MultiSizeMax a) where
  mempty =
    MultiSizeMax
      { cardinality = mempty,
        supportSize = mempty,
        getMax = mempty
      }

instance Functor MultiSizeMax where
  fmap f x =
    MultiSizeMax
      { cardinality = cardinality x,
        supportSize = supportSize x,
        getMax = fmap f . getMax $ x
      }

instance Eq a => Eq (MultiElem a) where
  x == y = getMultiElem x == getMultiElem y

instance Foldable MultiElem where
  foldr f z x = nTimes (fromInteger $ multiplicity x) (f $ getMultiElem x) z
    where
      nTimes :: Int -> (a -> a) -> a -> a
      nTimes n f = foldr1 (.) $ replicate n f

instance Functor MultiElem where
  fmap f x =
    MultiElem
      { getMultiElem = f $ getMultiElem x,
        multiplicity = multiplicity x
      }

instance Base.Measured (MultiElem a) (MultiSizeMax a) where
  measure x =
    MultiSizeMax
      { cardinality = Size $ multiplicity x,
        supportSize = Size 1,
        getMax = Max $ getMultiElem x
      }

instance Foldable MultiSet where
  foldr f z (MultiSet xs) = foldr f' z xs
    where
      f' = flip $ foldr f
  foldl f z (MultiSet xs) = foldl f' z xs
    where
      f' = foldl f

instance (Show a) => Show (MultiSet a) where
  showsPrec p xs =
    showParen (p > 10) $ showString "fromList " . shows (toList xs)

instance (Ord a) => Eq (MultiSet a) where
  xs == ys = xs `isSubsetOf` ys && ys `isSubsetOf` xs

empty :: MultiSet a
empty = MultiSet Base.Empty

singleton :: a -> MultiSet a
singleton = MultiSet . Base.singleton . multiElem

pattern Empty :: MultiSet a
pattern Empty = MultiSet Base.Empty

{- O(1) -}
null :: MultiSet a -> Bool
null Empty = True
null _ = False

{- O(1) -}
size :: MultiSet a -> Integer
size (MultiSet xs) = size' xs

{- O(1) -}
numUniqueElems :: MultiSet a -> Integer
numUniqueElems (MultiSet xs) = supportSize' xs

{- O(n) -}
toList :: MultiSet a -> [a]
toList = foldr (:) []

{- See fromFoldable -}
fromList :: Ord a => [a] -> MultiSet a
fromList = fromFoldable

{- See fromAscFoldable -}
fromAscList :: Eq a => [a] -> MultiSet a
fromAscList = fromAscFoldable

{- See fromDescFoldable -}
fromDescList :: Eq a => [a] -> MultiSet a
fromDescList = fromDescFoldable

{- See fromDistinctAscFoldable -}
fromDistinctAscList :: [a] -> MultiSet a
fromDistinctAscList = fromDistinctAscFoldable

{- See fromDistinctDescFoldable -}
fromDistinctDescList :: [a] -> MultiSet a
fromDistinctDescList = fromDistinctDescFoldable

{- O(log(i)), where i <= n/2 is distance from
   insert point to nearest end -}
insert :: (Ord a) => a -> MultiSet a -> MultiSet a
insert a (MultiSet xs) =
  MultiSet $ Base.modify (_insert a) ((Max a <=) . getMax) xs
  where
    _insert a Nothing = [multiElem a]
    _insert a (Just x) =
      if a == getMultiElem x
        then [incrementMultiElem x]
        else [multiElem a, x]

{- O(log(i)), where i <= n/2 is distance from
   delete point to nearest end -}
deleteOnce :: (Ord a) => a -> MultiSet a -> MultiSet a
deleteOnce a (MultiSet xs) = MultiSet $ Base.modify (_deleteOnce a) ((Max a <=) . getMax) xs
  where
    _deleteOnce a Nothing = []
    _deleteOnce a (Just x) =
      if a == getMultiElem x
        then maybeToList $ decrementMultiElem x
        else []

{- O(log(i)), where i <= n/2 is distance from
   delete point to nearest end -}
deleteEach :: (Ord a) => a -> MultiSet a -> MultiSet a
deleteEach a (MultiSet xs) = MultiSet $ Base.modify (_deleteEach a) ((Max a <=) . getMax) xs
  where
    _deleteEach a Nothing = []
    _deleteEach a (Just x) = [x | a /= getMultiElem x]

{- O(log(i)), where i <= n/2 is distance from
   element location to nearest end -}
count :: (Ord a) => a -> MultiSet a -> Integer
count a (MultiSet xs) =
  maybe 0 multiplicity (Base.lookup ((Max a <=) . getMax) xs)

{- O(nlog(n)) -}
map :: (Ord a, Ord b) => (a -> b) -> MultiSet a -> MultiSet b
map f = fromList . fmap f . toList

{- O(n). Does not check for monotonicity (that x < y => f x < f y) -}
mapMonotonic :: (Ord a, Ord b) => (a -> b) -> MultiSet a -> MultiSet b
mapMonotonic f (MultiSet xs) = MultiSet $ Bifunc.bimap (fmap f) (fmap f) xs

-- Set theoretic functions
{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
union :: (Ord a) => MultiSet a -> MultiSet a -> MultiSet a
union (MultiSet xs) (MultiSet ys) =
  MultiSet $ unionWith sumMultiElem getMax xs ys

{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
intersection :: (Ord a) => MultiSet a -> MultiSet a -> MultiSet a
intersection (MultiSet xs) (MultiSet ys) =
  MultiSet $ intersectionWith minMultiElem getMax xs ys

{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
difference :: (Ord a) => MultiSet a -> MultiSet a -> MultiSet a
difference (MultiSet xs) (MultiSet ys) =
  MultiSet $ differenceWith differenceMultiElem getMax xs ys

{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
isDisjointFrom :: (Ord a) => MultiSet a -> MultiSet a -> Bool
isDisjointFrom (MultiSet xs) (MultiSet ys) = _isDisjointFrom xs ys
  where
    _isDisjointFrom Base.Empty _ = True
    _isDisjointFrom _ Base.Empty = True
    _isDisjointFrom as (b Base.:<| bs') =
      case r of
        Base.Empty -> True
        x Base.:<| r' -> getMultiElem x /= getMultiElem b && _isDisjointFrom bs' r
      where
        (l, r) = Base.split (((<=) `on` getMax) $ Base.measure b) as

{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
isSubsetOf :: (Ord a) => MultiSet a -> MultiSet a -> Bool
isSubsetOf (MultiSet xs) (MultiSet ys) = _isSubsetOf xs ys
  where
    _isSubsetOf Base.Empty _ = True
    _isSubsetOf _ Base.Empty = False
    _isSubsetOf as bs@(b Base.:<| bs') =
      size' as <= size' bs && Base.null l && isSubsetRest
      where
        (l, r) = Base.split (((<=) `on` getMax) $ Base.measure b) as
        isSubsetRest =
          case r of
            Base.Empty -> True
            x Base.:<| r' ->
              if getMultiElem x == getMultiElem b
                then multiplicity x <= multiplicity b && _isSupsetOf bs' r'
                else _isSupsetOf bs' r
    _isSupsetOf _ Base.Empty = True
    _isSupsetOf Base.Empty _ = False
    _isSupsetOf as bs@(b Base.:<| bs') = size' as >= size' bs && isSupsetRest
      where
        (l, r) = Base.split (((<=) `on` getMax) $ Base.measure b) as
        isSupsetRest =
          case r of
            Base.Empty -> False
            (x Base.:<| r') ->
              getMultiElem x == getMultiElem b
                && multiplicity x >= multiplicity b
                && _isSubsetOf bs' r'

{- Probably amortized O(m log(n/m + 1),
   where m <= n lengths of xs and ys -}
isSupsetOf :: (Ord a) => MultiSet a -> MultiSet a -> Bool
isSupsetOf = flip isSubsetOf

{- O(n) -}
support :: (Ord a) => MultiSet a -> Set.Set a
support (MultiSet xs) =
  Set.fromDistinctAscList
    . toList
    . MultiSet
    . Bifunc.second (setMultiplicity 1)
    $ xs

-- Order statistics
{- O(1) -}
smallestElem :: MultiSet a -> Maybe a
smallestElem (MultiSet xs) =
  case xs of
    Base.Empty -> Nothing
    (a Base.:<| _) -> Just $ getMultiElem a

{- O(log(min(k, n-k))) -}
kthSmallestElem :: Integer -> MultiSet a -> Maybe a
kthSmallestElem k (MultiSet xs)
  | k < 1 = Nothing
  | otherwise = getMultiElem <$> Base.lookup ((Size k <=) . cardinality) xs

{- O(log(min(k, n-k))) -}
kthSmallestUniqueElem :: Integer -> MultiSet a -> Maybe a
kthSmallestUniqueElem k (MultiSet xs)
  | k < 1 = Nothing
  | otherwise = getMultiElem <$> Base.lookup ((Size k <=) . supportSize) xs

{- O(1) -}
largestElem :: MultiSet a -> Maybe a
largestElem (MultiSet xs) =
  case xs of
    Base.Empty -> Nothing
    (_ Base.:|> a) -> Just $ getMultiElem a

{- O(log(min(k, n-k))) -}
kthLargestElem :: Integer -> MultiSet a -> Maybe a
kthLargestElem k xs = kthSmallestElem (size xs - k + 1) xs

{- O(log(min(k, n-k))) -}
kthLargestUniqueElem :: Integer -> MultiSet a -> Maybe a
kthLargestUniqueElem k xs = kthSmallestUniqueElem (numUniqueElems xs - k + 1) xs

-- Generalized functions
{- O(nlog(n)) -}
fromFoldable :: (Foldable f, Ord a) => f a -> MultiSet a
fromFoldable = foldr insert empty

{- O(n) -}
fromAscFoldable :: (Foldable f, Eq a) => f a -> MultiSet a
fromAscFoldable =
  MultiSet . foldr _incrInsertElemLeft Base.empty
  where
    _incrInsertElemLeft a Base.Empty = Base.singleton $ multiElem a
    _incrInsertElemLeft a xs@(x Base.:<| r) =
      if a == getMultiElem x
        then incrementMultiElem x Base.:<| r
        else multiElem a Base.:<| xs

{- O(n) -}
fromDescFoldable :: (Foldable f, Eq a) => f a -> MultiSet a
fromDescFoldable =
  MultiSet . foldr _incrInsertElemRight Base.empty
  where
    _incrInsertElemRight a Base.Empty = Base.singleton $ multiElem a
    _incrInsertElemRight a xs@(l Base.:|> x) =
      if a == getMultiElem x
        then l Base.:|> incrementMultiElem x
        else xs Base.:|> multiElem a

{- O(n) -}
fromDistinctAscFoldable :: Foldable f => f a -> MultiSet a
fromDistinctAscFoldable = MultiSet . foldr _insertElemLeft Base.empty
  where
    _insertElemLeft a xs = multiElem a Base.:<| xs

{- O(n) -}
fromDistinctDescFoldable :: Foldable f => f a -> MultiSet a
fromDistinctDescFoldable = MultiSet . foldr _insertElemRight Base.empty
  where
    _insertElemRight a xs = xs Base.:|> multiElem a

-- Helper functions
size' :: forall a. Base.FingerTree (MultiSizeMax a) (MultiElem a) -> Integer
size' xs =
  let meas = Base.measure xs :: MultiSizeMax a
   in unSize . cardinality $ meas

supportSize' :: forall a. Base.FingerTree (MultiSizeMax a) (MultiElem a) -> Integer
supportSize' xs =
  let meas = Base.measure xs :: MultiSizeMax a
   in unSize . supportSize $ meas

multiElem :: a -> MultiElem a
multiElem a =
  MultiElem
    { getMultiElem = a,
      multiplicity = 1
    }

changeMultiplicity :: (Integer -> Integer) -> MultiElem a -> Maybe (MultiElem a)
changeMultiplicity f x
  | newMultiplicity <= 0 = Nothing
  | otherwise =
    Just $
      MultiElem
        { getMultiElem = getMultiElem x,
          multiplicity = newMultiplicity
        }
  where
    newMultiplicity = f (multiplicity x)

setMultiplicity :: Integer -> MultiElem a -> MultiElem a
setMultiplicity n = fromJust . changeMultiplicity (const n)

incrementMultiElem :: MultiElem a -> MultiElem a
incrementMultiElem = fromJust . changeMultiplicity (+ 1)

decrementMultiElem :: MultiElem a -> Maybe (MultiElem a)
decrementMultiElem = changeMultiplicity (subtract 1)

-- Assumes the two MultiElem have the same value
sumMultiElem :: MultiElem a -> MultiElem a -> MultiElem a
sumMultiElem x = fromJust . changeMultiplicity (+ multiplicity x)

-- Assumes the two MultiElem have the same value
differenceMultiElem :: MultiElem a -> MultiElem a -> Maybe (MultiElem a)
differenceMultiElem x y = changeMultiplicity (subtract . multiplicity $ y) x

-- Assumes the two MultiElem have the same value
minMultiElem :: MultiElem a -> MultiElem a -> MultiElem a
minMultiElem x = fromJust . changeMultiplicity (min . multiplicity $ x)
