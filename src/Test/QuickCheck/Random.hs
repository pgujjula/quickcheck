{-# OPTIONS_HADDOCK hide #-}
-- | A wrapper around the system random number generator. Internal QuickCheck module.
{-# LANGUAGE CPP #-}
#ifndef NO_SAFE_HASKELL
{-# LANGUAGE Trustworthy #-}
#endif
module Test.QuickCheck.Random where

import System.Random
#ifndef NO_SPLITMIX
import System.Random.SplitMix
#endif
import Data.Bits
#if MIN_VERSION_random(1,2,0)
import Data.Coerce
#endif

-- | The "standard" QuickCheck random number generator.
-- A wrapper around either 'SMGen' on GHC, or 'StdGen'
-- on other Haskell systems.
#ifdef NO_SPLITMIX
newtype QCGen = QCGen StdGen
#else
newtype QCGen = QCGen SMGen
#endif

instance Show QCGen where
  showsPrec n (QCGen g) s = showsPrec n g s
instance Read QCGen where
  readsPrec n xs = [(QCGen g, ys) | (g, ys) <- readsPrec n xs]

instance RandomGen QCGen where
#ifdef NO_SPLITMIX
  split (QCGen g) =
    case split g of
      (g1, g2) -> (QCGen g1, QCGen g2)

  genRange (QCGen g) = genRange g
  next (QCGen g) =
    case next g of
      (x, g') -> (x, QCGen g')
#else
  split (QCGen g) =
    case splitSMGen g of
      (g1, g2) -> (QCGen g1, QCGen g2)

#if MIN_VERSION_random(1,2,0)
  genWord8 (QCGen g) = coerce (genWord8 g)
  genWord16 (QCGen g) = coerce (genWord16 g)
  genWord32 (QCGen g) = coerce (genWord32 g)
  genWord64 (QCGen g) = coerce (genWord64 g)
  genWord32R r (QCGen g) = coerce (genWord32R r g)
  genWord64R r (QCGen g) = coerce (genWord64R r g)
  genShortByteString n (QCGen g) = coerce (genShortByteString n g)
#else
  genRange (QCGen g) = (minBound, maxBound)

  next (QCGen g) =
    case nextInt g of
      (x, g') -> (x, QCGen g')
#endif
#endif

newQCGen :: IO QCGen
#ifdef NO_SPLITMIX
newQCGen = fmap QCGen newStdGen
#else
newQCGen = fmap QCGen newSMGen
#endif

mkQCGen :: Int -> QCGen
#ifdef NO_SPLITMIX
mkQCGen n = QCGen (mkStdGen n)
#else
mkQCGen n = QCGen (mkSMGen (fromIntegral n))
#endif

-- Parameterised in order to make this code testable.
class Splittable a where
  left, right :: a -> a

instance Splittable QCGen where
  left = fst . split
  right = snd . split

-- The logic behind 'variant'. Given a random number seed, and an integer, uses
-- splitting to transform the seed according to the integer. We use a
-- prefix-free code so that calls to integerVariant n g for different values of
-- n are guaranteed to return independent seeds.
{-# INLINE integerVariant #-}
integerVariant :: Splittable a => Integer -> a -> a
integerVariant n g
  -- Use one bit to encode the sign, then use Elias gamma coding
  -- (https://en.wikipedia.org/wiki/Elias_gamma_coding) to do the rest.
  -- Actually, the first bit encodes whether n >= 1 or not;
  -- this has the advantage that both 0 and 1 get short codes.
  | n >= 1 = gamma n $! left g
  | otherwise = gamma (1-n) $! right g
  where
    gamma n =
      encode k . zeroes k
      where
        k = ilog2 n

        encode (-1) g = g
        encode k g
          | testBit n k =
            encode (k-1) $! right g
          | otherwise =
            encode (k-1) $! left g

        zeroes 0 g = g
        zeroes k g = zeroes (k-1) $! left g

    ilog2 1 = 0
    ilog2 n = 1 + ilog2 (n `div` 2)
