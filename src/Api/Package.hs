module Api.Package (resource) where

import           Control.Monad.Except
import           Control.Monad.Reader
import           Data.Aeson
import qualified Data.ByteString.Lazy as L
import           Data.Text            (Text, pack, unpack)
import           Rest
import           Rest.Info
import qualified Rest.Resource        as R
import           Rest.ShowUrl
import           System.Directory

import           Api.Types
import           BuildReport

data Identifier = Name Text

instance Info Identifier where describe _ = "identifier"

instance ShowUrl Identifier where
  showUrl (Name t) = unpack t

type WithPackage = ReaderT Identifier Root

resource :: Resource Root WithPackage Identifier () Void
resource = mkResourceReader
  { R.name   = "package"
  , R.schema = withListing () $ named [("name", singleBy (Name . pack))]
  , R.get    = Just get
  , R.list   = const list
  }

list :: ListHandler Root
list = mkListing jsonO handler
  where
    handler :: Range -> ExceptT Reason_ Root [Text]
    handler _ =
      map pack . map (reverse . drop 5) . filter (("nosj." ==) . take 5) . map reverse <$> liftIO (getDirectoryContents "report/")

get :: Handler WithPackage
get = mkConstHandler jsonO handler
  where
    handler :: ExceptT Reason_ WithPackage ReportDataJson
    handler = do
      Name t <- ask
      let fp = "report/" ++ unpack t ++ ".json"
      exists <- liftIO $ doesFileExist fp
      unless exists $ throwError NotFound
      f <- liftIO $ L.readFile fp
      let x = decode f
      maybe (throwError Busy) (return . reportDataJson) x
