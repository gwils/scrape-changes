module Network.ScrapeChanges.Internal (
  defaultScrapeConfig
, validateScrapeConfig
, validateCronSchedule
, hash
, readLatestHash
, saveHash
) where
import Prelude hiding (filter)
import Data.Validation
import Data.List.NonEmpty
import Data.ByteString.Strict.Lens
import Control.Lens
import qualified Network.URI as U
import qualified Data.Foldable as F
import Network.ScrapeChanges.Internal.Domain
import qualified Data.ByteString.Lens as ByteStringLens
import qualified Data.Text.Lens as TextLens
import qualified Text.Email.Validate as EmailValidate
import qualified Data.Attoparsec.Text as AttoparsecText
import qualified System.Cron.Parser as CronParser
import qualified Data.Digest.CRC32 as CRC32
import Control.Monad (void)
import Data.Hashable (Hashable)

invalidMailAddr :: MailAddr
invalidMailAddr = MailAddr { _mailAddrName = Nothing, _mailAddr = "invalidmail" }

-- TODO require scrapeInfoUrl, mailFrom, mailTo
defaultScrapeConfig :: ScrapeConfig t
defaultScrapeConfig = ScrapeConfig {
  _scrapeInfoUrl = ""
, _scrapeInfoCallbackConfig = MailConfig defaultMail
} where defaultMail :: Mail
        defaultMail = Mail {
          _mailFrom =  invalidMailAddr :| []
        , _mailTo = invalidMailAddr :| []
        , _mailSubject = ""
        , _mailBody = ""
        }

validateScrapeConfig :: ScrapeConfig t -> ScrapeValidation (ScrapeConfig t)
validateScrapeConfig si = 
  let toUnit = void
      urlValidation = validateUrl $ si ^. scrapeInfoUrl
      callbackValidation = validateCallbackConfig $ si ^. scrapeInfoCallbackConfig
  in const si <$> F.sequenceA_ [toUnit urlValidation, toUnit callbackValidation]

validateMailConfig :: Mail -> ScrapeValidation Mail
validateMailConfig m = 
  let mailAddrs t = fromList $ m ^.. (t . traverse . mailAddr)
      isInvalidMailAddr = (not . EmailValidate.isValid . (^. ByteStringLens.packedChars))
      mailFromAddrs = mailAddrs mailFrom
      invalidMailFromAddrs = MailConfigInvalidMailFromAddr <$> (isInvalidMailAddr `filter` mailFromAddrs)
      mailToAddrs = mailAddrs mailTo
      invalidMailToAddrs = MailConfigInvalidMailToAddr <$> (isInvalidMailAddr `filter` mailToAddrs)
      ok = pure m
  in const m <$> F.sequenceA_ [
    if null invalidMailFromAddrs then ok else AccFailure invalidMailFromAddrs
  , if null invalidMailToAddrs then ok else AccFailure invalidMailToAddrs
  ]

validateCallbackConfig :: CallbackConfig t -> ScrapeValidation (CallbackConfig t)
validateCallbackConfig (MailConfig m) = MailConfig <$> validateMailConfig m
validateCallbackConfig c@(OtherConfig _) = pure c

validateUrl :: String -> ScrapeValidation String
validateUrl s = let uriMaybe = U.parseAbsoluteURI s
                    isAbsoluteUrl = U.isAbsoluteURI s 
                    protocolMaybe = U.uriScheme <$> uriMaybe
                    isHttp = (=="http:") `F.all` protocolMaybe
                    ok = pure s
                in const s <$> F.sequenceA_ [
                     if isAbsoluteUrl then ok else AccFailure [UrlNotAbsolute]
                   , if isHttp then ok else AccFailure [UrlProtocolInvalid]
                   ]

validateCronSchedule :: CronSchedule -> ScrapeValidation CronSchedule
validateCronSchedule c = 
  let mapFailure = _Failure %~ \s -> [CronScheduleInvalid s]
      setSuccess = _Success .~ c
      either' = AttoparsecText.parseOnly CronParser.cronSchedule (c ^. TextLens.packed)
      mappedEither' = mapFailure . setSuccess $ either'
  in  mappedEither' ^. _AccValidation

hash :: String -> String
hash s = let packedS = s ^. packedChars
             h = CRC32.crc32 packedS
         in show h 

readLatestHash :: (Hashable t) => t -> IO String
readLatestHash = undefined

saveHash :: (Hashable t) => t -> IO ()
saveHash = undefined
