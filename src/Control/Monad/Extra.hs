{-# LANGUAGE ConstraintKinds, CPP #-}

-- | Extra functions for "Control.Monad".
--   These functions provide looping, list operations and booleans.
--   If you need a wider selection of monad loops and list generalisations,
--   see <https://hackage.haskell.org/package/monad-loops monad-loops>.
module Control.Monad.Extra(
    module Control.Monad,
    whenJust, whenJustM,
    whenMaybe, whenMaybeM,
    unit,
    maybeM, eitherM,
    -- * Loops
    loop, loopM, whileM,
    -- * Lists
    partitionM, concatMapM, concatForM, mconcatMapM, mapMaybeM, findM, firstJustM,
    fold1M, fold1M_,
    -- * Booleans
    whenM, unlessM, ifM, notM, (||^), (&&^), orM, andM, anyM, allM
    ) where

import Control.Monad
import Control.Exception.Extra
import Data.Maybe
import Data.Foldable
import Control.Applicative
import Data.Monoid
import Prelude hiding (foldr)

-- General utilities

-- | Perform some operation on 'Just', given the field inside the 'Just'.
--
-- > whenJust Nothing  print == return ()
-- > whenJust (Just 1) print == print 1
whenJust :: Applicative m => Maybe a -> (a -> m ()) -> m ()
whenJust mg f = maybe (pure ()) f mg

-- | Like 'whenJust', but where the test can be monadic.
whenJustM :: Monad m => m (Maybe a) -> (a -> m ()) -> m ()
-- Can't reuse whenMaybe on GHC 7.8 or lower because Monad does not imply Applicative
whenJustM mg f = maybe (return ()) f =<< mg


-- | Like 'when', but return either 'Nothing' if the predicate was 'False',
--   of 'Just' with the result of the computation.
--
-- > whenMaybe True  (print 1) == fmap Just (print 1)
-- > whenMaybe False (print 1) == return Nothing
whenMaybe :: Applicative m => Bool -> m a -> m (Maybe a)
whenMaybe b x = if b then Just <$> x else pure Nothing

-- | Like 'whenMaybe', but where the test can be monadic.
whenMaybeM :: Monad m => m Bool -> m a -> m (Maybe a)
-- Can't reuse whenMaybe on GHC 7.8 or lower because Monad does not imply Applicative
whenMaybeM mb x = do
    b <- mb
    if b then liftM Just x else return Nothing


-- | The identity function which requires the inner argument to be @()@. Useful for functions
--   with overloaded return types.
--
-- > \(x :: Maybe ()) -> unit x == x
unit :: m () -> m ()
unit = id


-- | Monadic generalisation of 'maybe'.
maybeM :: Monad m => m b -> (a -> m b) -> m (Maybe a) -> m b
maybeM n j x = maybe n j =<< x


-- | Monadic generalisation of 'either'.
eitherM :: Monad m => (a -> m c) -> (b -> m c) -> m (Either a b) -> m c
eitherM l r x = either l r =<< x

-- | A variant of 'foldM' that has no base case, and thus may only be applied to non-empty lists.
--
-- > fold1M (\x y -> Just x) [] == undefined
-- > fold1M (\x y -> Just $ x + y) [1, 2, 3] == Just 6
fold1M :: (Partial, Monad m) => (a -> a -> m a) -> [a] -> m a
fold1M f (x:xs) = foldM f x xs
fold1M f xs = error "fold1M: empty list"

-- | Like 'fold1M' but discards the result.
fold1M_ :: (Partial, Monad m) => (a -> a -> m a) -> [a] -> m ()
fold1M_ f xs = fold1M f xs >> return ()


-- Data.List for Monad

-- | A version of 'partition' that works with a monadic predicate.
--
-- > partitionM (Just . even) [1,2,3] == Just ([2], [1,3])
-- > partitionM (const Nothing) [1,2,3] == Nothing
partitionM :: Monad m => (a -> m Bool) -> [a] -> m ([a], [a])
partitionM f [] = return ([], [])
partitionM f (x:xs) = do
    res <- f x
    (as,bs) <- partitionM f xs
    return ([x | res]++as, [x | not res]++bs)


-- | A version of 'concatMap' that works with a monadic predicate.
concatMapM :: Monad m => (a -> m [b]) -> [a] -> m [b]
{-# INLINE concatMapM #-}
concatMapM op = foldr f (return [])
    where f x xs = do x <- op x; if null x then xs else do xs <- xs; return $ x++xs

-- | Like 'concatMapM', but has its arguments flipped, so can be used
--   instead of the common @fmap concat $ forM@ pattern.
concatForM :: Monad m => [a] -> (a -> m [b]) -> m [b]
concatForM = flip concatMapM

-- | A version of 'mconcatMap' that works with a monadic predicate.
mconcatMapM :: (Monad m, Monoid b) => (a -> m b) -> [a] -> m b
mconcatMapM f = liftM mconcat . mapM f

-- | A version of 'mapMaybe' that works with a monadic predicate.
mapMaybeM :: Monad m => (a -> m (Maybe b)) -> [a] -> m [b]
{-# INLINE mapMaybeM #-}
mapMaybeM op = foldr f (return [])
    where f x xs = do x <- op x; case x of Nothing -> xs; Just x -> do xs <- xs; return $ x:xs

-- Looping

-- | A looping operation, where the predicate returns 'Left' as a seed for the next loop
--   or 'Right' to abort the loop.
--
-- > loop (\x -> if x < 10 then Left $ x * 2 else Right $ show x) 1 == "16"
loop :: (a -> Either a b) -> a -> b
loop act x = case act x of
    Left x -> loop act x
    Right v -> v

-- | A monadic version of 'loop', where the predicate returns 'Left' as a seed for the next loop
--   or 'Right' to abort the loop.
loopM :: Monad m => (a -> m (Either a b)) -> a -> m b
loopM act x = do
    res <- act x
    case res of
        Left x -> loopM act x
        Right v -> return v

-- | Keep running an operation until it becomes 'False'. As an example:
--
-- @
-- whileM $ do sleep 0.1; notM $ doesFileExist "foo.txt"
-- readFile "foo.txt"
-- @
--
--   If you need some state persisted between each test, use 'loopM'.
whileM :: Monad m => m Bool -> m ()
whileM act = do
    b <- act
    when b $ whileM act

-- Booleans

-- | Like 'when', but where the test can be monadic.
whenM :: Monad m => m Bool -> m () -> m ()
whenM b t = ifM b t (return ())

-- | Like 'unless', but where the test can be monadic.
unlessM :: Monad m => m Bool -> m () -> m ()
unlessM b f = ifM b (return ()) f

-- | Like @if@, but where the test can be monadic.
ifM :: Monad m => m Bool -> m a -> m a -> m a
ifM b t f = do b <- b; if b then t else f

-- | Like 'not', but where the test can be monadic.
notM :: Functor m => m Bool -> m Bool
notM = fmap not

-- | The lazy '||' operator lifted to a monad. If the first
--   argument evaluates to 'True' the second argument will not
--   be evaluated.
--
-- > Just True  ||^ undefined  == Just True
-- > Just False ||^ Just True  == Just True
-- > Just False ||^ Just False == Just False
(||^) :: Monad m => m Bool -> m Bool -> m Bool
(||^) a b = ifM a (return True) b

-- | The lazy '&&' operator lifted to a monad. If the first
--   argument evaluates to 'False' the second argument will not
--   be evaluated.
--
-- > Just False &&^ undefined  == Just False
-- > Just True  &&^ Just True  == Just True
-- > Just True  &&^ Just False == Just False
(&&^) :: Monad m => m Bool -> m Bool -> m Bool
(&&^) a b = ifM a b (return False)

-- | A version of 'any' lifted to a monad. Retains the short-circuiting behaviour.
--
-- > anyM Just [False,True ,undefined] == Just True
-- > anyM Just [False,False,undefined] == undefined
-- > \(f :: Int -> Maybe Bool) xs -> anyM f xs == orM (map f xs)
-- > anyM Just (Just True) == Just True
-- > anyM Just Nothing == Just False
#if __GLASGOW_HASKELL__ < 710
anyM :: (Foldable f, Monad m) => (a -> m Bool) -> f a -> m Bool
#else
anyM :: (Foldable f, Functor m, Monad m) => (a -> m Bool) -> f a -> m Bool
#endif
anyM p = fmap isJust . findM p

-- | A version of 'all' lifted to a monad. Retains the short-circuiting behaviour.
--
-- > allM Just [True,False,undefined] == Just False
-- > allM Just [True,True ,undefined] == undefined
-- > \(f :: Int -> Maybe Bool) xs -> anyM f xs == orM (map f xs)
-- > allM Just (Just False) == Just False
-- > allM Just Nothing == Just True
#if __GLASGOW_HASKELL__ < 710
allM :: (Foldable f, Monad m) => (a -> m Bool) -> f a -> m Bool
#else
allM :: (Foldable f, Functor m, Monad m) => (a -> m Bool) -> f a -> m Bool
#endif
allM p = notM . anyM (notM . p)

-- | A version of 'or' lifted to a monad. Retains the short-circuiting behaviour.
--
-- > orM [Just False,Just True ,undefined] == Just True
-- > orM [Just False,Just False,undefined] == undefined
-- > \xs -> Just (or xs) == orM (map Just xs)
-- > orM (Just $ Just False) == Just False
-- > orM (Just Nothing) == Nothing
-- > orM Nothing == Just False
orM :: (Foldable f, Monad m) => f (m Bool) -> m Bool
orM = anyM id

-- | A version of 'and' lifted to a monad. Retains the short-circuiting behaviour.
--
-- > andM [Just True,Just False,undefined] == Just False
-- > andM [Just True,Just True ,undefined] == undefined
-- > \xs -> Just (and xs) == andM (map Just xs)
-- > andM (Just $ Just False) == Just False
-- > andM (Just Nothing) == Nothing
-- > andM Nothing == Just True
andM :: (Foldable f, Monad m) => f (m Bool) -> m Bool
andM = allM id

-- Searching

-- | Like 'find', but where the test can be monadic.
--
-- > findM (Just . isUpper) "teST"             == Just (Just 'S')
-- > findM (Just . isUpper) "test"             == Just Nothing
-- > findM (Just . const True) ["x",undefined] == Just (Just "x")
-- > findM (Just . isUpper) (Just 'A') == Just (Just 'A')
-- > findM (Just . isUpper) Nothing == Just Nothing
findM :: (Foldable f, Monad m) => (a -> m Bool) -> f a -> m (Maybe a)
findM p = helper . toList
    where helper [] = return Nothing
          helper (x:xs) = ifM (p x) (return $ Just x) (findM p xs)

-- | Like 'findM', but also allows you to compute some additional information in the predicate.
-- > firstJustM (Just . fmap not) [Just True, Nothing] == Just (Just False)
-- > firstJustM (Just . fmap not) [Just False] == Just (Just True)
-- > firstJustM (Just . fmap not) (Just $ Just False) == Just (Just True)
-- > firstJustM (Just . fmap not) Nothing == Just Nothing
firstJustM :: (Foldable f, Monad m) => (a -> m (Maybe b)) -> f a -> m (Maybe b)
firstJustM p = helper . toList
    where helper [] = return Nothing
          helper (x:xs) = maybe (firstJustM p xs) (return . Just) =<< p x
