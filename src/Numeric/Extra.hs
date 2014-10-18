
module Numeric.Extra(
    module Numeric,
    showDP,
    intToDouble, intToFloat, floatToDouble, doubleToFloat
    ) where

import Numeric
import Control.Arrow

---------------------------------------------------------------------
-- Data.String

showDP :: RealFloat a => Int -> a -> String
showDP n x = a ++ (if n > 0 then "." else "") ++ b ++ replicate (n - length b) '0'
    where (a,b) = second (drop 1) $ break (== '.') $ showFFloat (Just n) x ""


---------------------------------------------------------------------
-- Numeric

intToDouble :: Int -> Double
intToDouble = fromIntegral

intToFloat :: Int -> Float
intToFloat = fromIntegral

floatToDouble :: Float -> Double
floatToDouble = realToFrac

doubleToFloat :: Double -> Float
doubleToFloat = realToFrac

