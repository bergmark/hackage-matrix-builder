{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Build-types and associated primitive helpers
module BuildTypes
    ( module BuildTypes
    , ByteString
    , ExitCode(..)
    , Generic
    , NFData
    , Natural
    , Binary
    , Set.Set
    , Map.Map
    , Text
    , FromJSON
    , ToJSON
    ) where

import           Data.JSON.Schema
import           Data.String.ToString
import           Data.String
import           Data.Aeson
import           Data.Text (Text)
import           Control.Monad
import           Data.Aeson (FromJSON,ToJSON)
import qualified Data.Aeson as J
import           Generics.Generic.Aeson
import           Data.Bifunctor
import           Data.Bitraversable
import           Data.Binary
import           Data.Bits
import           Data.Hashable
import           Data.List
import qualified Data.Map as Map
import           Data.Maybe
import           Data.Monoid ((<>))
import qualified Data.Set as Set
import           Data.Text (Text)
import           Data.Version
import           GHC.Generics
import           Numeric.Natural
import           System.Exit
import           Text.ParserCombinators.ReadP (readP_to_S, ReadP)

import           Control.DeepSeq
import qualified Crypto.Hash.SHA256 as SHA256
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Char8 as BC

-- orphans
deriving instance Generic ExitCode
deriving instance NFData ExitCode

-- | Known GHC versions
data GhcVer = GHC_7_00
            | GHC_7_02
            | GHC_7_04
            | GHC_7_06
            | GHC_7_08
            | GHC_7_10
            deriving (Eq,Ord,Bounded,Enum,Read,Show,Hashable,Binary,NFData,Generic,FromJSON,ToJSON)

instance ToString GhcVer where
  toString = show
instance IsString GhcVer where
  fromString = \case
    "GHC_7_00" -> GHC_7_00
    "GHC_7_02" -> GHC_7_02
    "GHC_7_04" -> GHC_7_04
    "GHC_7_06" -> GHC_7_06
    "GHC_7_08" -> GHC_7_08
    "GHC_7_10" -> GHC_7_10



ghcVers :: [GhcVer]
ghcVers = [minBound..maxBound]

ghcVerStr :: GhcVer -> String
ghcVerStr = drop 4 . show

parseGhcVer :: String -> Maybe GhcVer
parseGhcVer s = lookup s [ (ghcVerStr v, v) | v <- [minBound..maxBound] ]

parseGhcVer' :: String -> GhcVer
parseGhcVer' s = fromMaybe (error $ "parseGhcVer " ++ show s) . parseGhcVer $ s

----------------------------------------------------------------------------

newtype PkgName = PkgName String
                deriving (Show,Read,Eq,Ord,Generic,NFData,Hashable,Binary,FromJSON,ToJSON)

instance JSONSchema PkgName where schema _ = Any

instance IsString PkgName where fromString = PkgName
instance ToString PkgName where toString = unPkgName

unPkgName :: PkgName -> String
unPkgName (PkgName s) = s

-- | Our variant of 'Data.Version.Version'
newtype PkgVer = PkgVer [Word]
               deriving (Show,Read,Eq,Ord,Generic,NFData,Hashable,Binary,FromJSON,ToJSON)

--instance ToJSON     PkgVer where toJSON    = toJSON . toString
--instance FromJSON   PkgVer where parseJSON = fmap fromString . parseJSON
instance JSONSchema PkgVer where schema _  = Any

instance IsString PkgVer where
  fromString = fromMaybe (error "PkgVer.fromString") . parsePkgVer

instance ToString PkgVer where
  toString = showPkgVer

showPkgVer :: PkgVer -> String
showPkgVer (PkgVer v) = concat . intersperse "." . map show $ v

-- | Dual to 'showPkgVer'
parsePkgVer :: String -> Maybe PkgVer
parsePkgVer v0 = do
    Version v [] <- runReadP parseVersion v0
    PkgVer <$> mapM toIntegralSized v
  where
    runReadP :: ReadP a -> String -> Maybe a
    runReadP p s = listToMaybe [ x | (x,"") <- readP_to_S p s ]

-- | Non-total 'parsePkgVer'
parsePkgVer' :: String -> PkgVer
parsePkgVer' s = fromMaybe (error $ "parsePkgVer " ++ show s) . parsePkgVer $ s

majMinVer :: PkgVer -> (Word,Word,Word)
majMinVer (PkgVer v) = case v of
    []        -> (0,0,0)
    [a]       -> (a,0,0)
    [a,b]     -> (a,b,0)
    (a:b:c:_) -> (a,b,c)

majorVer :: PkgVer -> (Word,Word)
majorVer v = let (a,b,_) = majMinVer v in (a,b)

----------------------------------------------------------------------------

type PkgRev  = Word

type PkgId   = (PkgName,PkgVer)

showPkgId :: PkgId -> String
showPkgId (PkgName n,v)
  | null vs   = n -- version-less package id
  | otherwise = n <> "-" <> vs
  where
    vs = showPkgVer v


parsePkgId :: String -> Maybe PkgId
parsePkgId s = do
    guard (not $ null pkgn)
    pkgv <- parsePkgVer pkgvs
    let pkgid = (PkgName pkgn,pkgv)
    guard (showPkgId pkgid == s)
    return pkgid
  where
    slen = length s
    pkgvs = reverse . takeWhile (`elem` ('.':['0'..'9'])) . reverse $ s
    pkgn = take (slen - (length pkgvs + 1)) s

parsePkgId' :: String -> PkgId
parsePkgId' s = fromMaybe (error $ "parsePkgId " ++ show s) . parsePkgId $ s

----------------------------------------------------------------------------

type SbId = String -- <pkgname>-<pkgver>-<dephash>

mkSbId :: PkgId -> [PkgId] -> SbId
mkSbId pkgid deps = showPkgId pkgid <> "_" <> hashDeps deps

unSbId :: SbId -> (PkgId,String)
unSbId sbid = force $ bimap parsePkgId' tail $ break (=='_') sbid

----------------------------------------------------------------------------

data DryResult
    = AlreadyInstalled !PkgId           -- ^ target already installed, nothing to do
    | InstallPlan      !PkgId [PkgId] [PkgId]  -- ^ install-plan for target, required
                                               -- sub-targets, and reinstall-affected
                                               -- packages
    | NoInstallPlan    !Int !ByteString -- ^ failed to find valid install plan
    deriving (Show,Read,Generic,NFData)

type SolverData = (SolveResult, [((Word,Word),SolveResult)])

data SolveResult
    = SolveNoOp !PkgVer
    | SolveInstall !PkgVer
    | SolveNoInstall
    deriving (Show,Read,Generic,NFData,FromJSON,ToJSON)

solveResultToPkgVer :: SolveResult -> Maybe PkgVer
solveResultToPkgVer (SolveNoOp v)    = Just v
solveResultToPkgVer (SolveInstall v) = Just v
solveResultToPkgVer SolveNoInstall   = Nothing

dryToSolveResult :: DryResult -> SolveResult
dryToSolveResult = \case
    AlreadyInstalled pid -> SolveNoOp (snd pid)
    InstallPlan pid _ _  -> SolveInstall (snd pid)
    NoInstallPlan _ _    -> SolveNoInstall

data SbExitCode
    = SbExitOk
    | SbExitFail [SbId] -- list contains indirect failures, i.e. the
                        -- ids of direct and indirect build-deps whose
                        -- indirect-failure list was empty
    deriving (Show,Read,Generic,NFData,FromJSON,ToJSON)

-- | Represents build outcome status with associated meta-info
data BuildResult
    = BuildOk
    | BuildNop
    | BuildNoIp
    | BuildFail !Text -- build-output
    | BuildFailDeps [(PkgId,Text)] -- failed deps & associated build-outputs
    deriving (Show,Read,Generic,NFData,FromJSON,ToJSON)

--instance ToJSON     BuildResult where toJSON    = gtoJson
--instance FromJSON   BuildResult where parseJSON = gparseJson
instance JSONSchema BuildResult where schema _  = Any

hashDeps :: [PkgId] -> String
hashDeps = BC.unpack .B16.encode . SHA256.hash . BC.pack . show

type PkgVerPfx = [Word]

data PkgCstr = PkgCstrEq  !PkgVer
             | PkgCstrPfx PkgVerPfx  -- ^ @PkgCstrPfx []@ means no constraint at all
             | PkgCstrInstalled
             deriving (Show,Read,Generic,NFData,Eq,Ord,FromJSON,ToJSON)

cstrFromPkgId :: PkgId -> (PkgName,PkgCstr)
cstrFromPkgId = fmap PkgCstrEq

showPkgCstr :: (PkgName,PkgCstr) -> String
showPkgCstr (PkgName n,PkgCstrEq v)      = n <> " ==" <> showPkgVer v
showPkgCstr (PkgName n,PkgCstrPfx v)     = n <> " ==" <> (concat $ intersperse "." (map show v ++ ["*"]))
showPkgCstr (PkgName n,PkgCstrInstalled) = n <> " installed"

----------------------------------------------------------------------------
-- Some semi-orphans (they can only become full orphans, if aeson
-- decides to define instances paremtric in the key-type of the Map,
-- which it doesn't right now) to support encoding 'ReportData'

instance ToJSON v => ToJSON (Map.Map PkgVer v) where
    toJSON = J.toJSON . Map.toList

instance FromJSON v => FromJSON (Map.Map PkgVer v) where
    parseJSON v = Map.fromList <$> J.parseJSON v

----

-- | Since GhcVer gets encoded to a string anyway, we can use JSON
-- objects for GhcVer-indexed maps
instance ToJSON v => ToJSON (Map.Map GhcVer v) where
    toJSON = J.toJSON . Map.fromList . map f . Map.toList
      where
        f (J.toJSON -> J.String l,v) = (l,v)
        f _                          = error "ToJSON(Map GhcVer _)"

instance FromJSON v => FromJSON (Map.Map GhcVer v) where
    parseJSON v = do
        entries <- Map.toList <$> J.parseJSON v
        Map.fromList <$> mapM (bitraverse (J.parseJSON . J.String) pure) entries

----

instance ToJSON v => ToJSON (Map.Map PkgVerPfx v) where
    toJSON = J.toJSON . Map.toList

instance FromJSON v => FromJSON (Map.Map PkgVerPfx v) where
    parseJSON v = Map.fromList <$> J.parseJSON v
