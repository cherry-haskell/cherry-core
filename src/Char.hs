-- | Functions for working with characters. Character literals are enclosed in `'a'` pair of single quotes.
--
-- Characters
-- @docs Char
--
-- ASCII Letters
-- @docs isUpper, isLower, isAlpha, isAlphaNum
--
-- Digits
-- @docs isDigit, isOctDigit, isHexDigit
--
-- Conversion
-- @docs toUpper, toLower
--
-- Unicode Code Points
-- @docs toCode, fromCode
--
-- Unsupported functions Since we don't have a browser and we don't have a
-- default locale, functions like `toLocaleUpper` and `toLocaleUpper` are not
-- supported. If you need something like that you can check out the `text-icu`
-- package which provides functions like `toUpper :: LocaleName -> Text -> Text`.
module Char
  ( -- * Characters
    Char

    -- * ASCII Letters
  , isUpper, isLower, isAlpha, isAlphaNum

    -- * Digits
  , isDigit, isOctDigit, isHexDigit

    -- * Conversion
  . toUpper, toLower

    -- * Unicode Code Points
  , toCode, fromCode
  )
where

import Basics ((&&), (<<), (<=), Bool (..), Int)
import Prelude (Applicative, Char, Eq, Functor, Monad, Num, Ord, Show, flip, fromIntegral, mappend, mconcat, otherwise, pure)
import qualified Data.Char
import qualified Cherry.Internal as Internal


{-| A `Char` is a single [unicode](https://en.wikipedia.org/wiki/Unicode) character:

  >  'a'
  >  '0'
  >  'Z'
  >  '?'
  >  '"'
  >  'Σ'
  >  '🙈'
  >
  >  '\t'
  >  '\"'
  >  '\''
  >  '\u{1F648}' -- '🙈'

**Note 1:** You _cannot_ use single quotes around multiple characters like in
JavaScript. This is how we distinguish [`String`](String#String) and `Char`
values in syntax.

**Note 2:** You can use the unicode escapes from `\u{0000}` to `\u{10FFFF}` to
represent characters by their code point. You can also include the unicode
characters directly. Using the escapes can be better if you need one of the
many whitespace characters with different widths.

-}
type Char =
  Prelude.Char


{-| Detect upper case ASCII characters.

  >  isUpper 'A' == True
  >  isUpper 'B' == True
  >  ...
  >  isUpper 'Z' == True
  >
  >  isUpper '0' == False
  >  isUpper 'a' == False
  >  isUpper '-' == False
  >  isUpper 'Σ' == False

-}
isUpper :: Char -> Bool
isUpper = Data.Char.isUpper


{-| Detect lower case ASCII characters.

  >  isLower 'a' == True
  >  isLower 'b' == True
  >  ...
  >  isLower 'z' == True
  >
  >  isLower '0' == False
  >  isLower 'A' == False
  >  isLower '-' == False
  >  isLower 'π' == False

-}
isLower :: Char -> Bool
isLower = Data.Char.isLower


{-| Detect upper case and lower case ASCII characters.

  >  isAlpha 'a' == True
  >  isAlpha 'b' == True
  >  isAlpha 'E' == True
  >  isAlpha 'Y' == True
  >
  >  isAlpha '0' == False
  >  isAlpha '-' == False
  >  isAlpha 'π' == False

-}
isAlpha :: Char -> Bool
isAlpha = Data.Char.isAlpha


{-| Detect upper case and lower case ASCII characters.

  >  isAlphaNum 'a' == True
  >  isAlphaNum 'b' == True
  >  isAlphaNum 'E' == True
  >  isAlphaNum 'Y' == True
  >  isAlphaNum '0' == True
  >  isAlphaNum '7' == True
  >
  >  isAlphaNum '-' == False
  >  isAlphaNum 'π' == False

-}
isAlphaNum :: Char -> Bool
isAlphaNum = Data.Char.isAlphaNum


{-| Detect digits `0123456789`

  >  isDigit '0' == True
  >  isDigit '1' == True
  >  ...
  >  isDigit '9' == True
  >
  >  isDigit 'a' == False
  >  isDigit 'b' == False
  >  isDigit 'A' == False

-}
isDigit :: Char -> Bool
isDigit = Data.Char.isDigit


{-| Detect octal digits `01234567`

  >  isOctDigit '0' == True
  >  isOctDigit '1' == True
  >  ...
  >  isOctDigit '7' == True
  >
  >  isOctDigit '8' == False
  >  isOctDigit 'a' == False
  >  isOctDigit 'A' == False

-}
isOctDigit :: Char -> Bool
isOctDigit = Data.Char.isOctDigit


{-| Detect hexadecimal digits `0123456789abcdefABCDEF`
-}
isHexDigit :: Char -> Bool
isHexDigit = Data.Char.isHexDigit


{-| Convert to upper case. -}
toUpper :: Char -> Char
toUpper = Data.Char.toUpper


{-| Convert to lower case. -}
toLower :: Char -> Char
toLower = Data.Char.toLower


{-| Convert to the corresponding Unicode [code point](https://en.wikipedia.org/wiki/Code_point).

  >  toCode 'A' == 65
  >  toCode 'B' == 66
  >  toCode '木' == 0x6728
  >  toCode '𝌆' == 0x1D306
  >  toCode '😃' == 0x1F603

-}
toCode :: Char -> Int
toCode = fromIntegral << Data.Char.ord


{-| Convert a Unicode [code point](https://en.wikipedia.org/wiki/Code_point) to a character.

  >  fromCode 65      == 'A'
  >  fromCode 66      == 'B'
  >  fromCode 0x6728  == '木'
  >  fromCode 0x1D306 == '𝌆'
  >  fromCode 0x1F603 == '😃'
  >  fromCode -1      == '�'

The full range of unicode is from `0` to `0x10FFFF`. With numbers outside that
range, you get [the replacement character](https://en.wikipedia.org/wiki/Specials_(Unicode_block)#Replacement_character).

-}
fromCode :: Int -> Char
fromCode value =
  if 0 <= value && value <= 0x10FFFF then
    Data.Char.chr (fromIntegral value)
  else
    '\xfffd'
