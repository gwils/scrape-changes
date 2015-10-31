{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Network.ScrapeChanges.Internal.Test where
import Prelude hiding (filter)
import Network.ScrapeChanges.Internal as SUT
import Network.ScrapeChanges.Internal.Domain as Domain
import qualified Network.ScrapeChanges as SC
import qualified Data.Maybe as M
import qualified Data.List as L
import Data.List.NonEmpty
import Test.HUnit hiding (assertFailure)
import Test.QuickCheck
import Test.Framework as TF
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2
import Control.Lens
import qualified Data.ByteString.Lens as ByteStringLens
import qualified Data.Validation as V
import qualified Text.Email.Validate as EmailValidate

newtype NCronSchedule = NCronSchedule { nCronScheduleRun :: String } deriving Show

instance Arbitrary NCronSchedule where 
    arbitrary = NCronSchedule <$> oneof [pure correctCronSchedule, arbitrary]

correctCronSchedule :: String
correctCronSchedule = "*/2 * 3 * 4,5,6"

emailAddressGen :: Gen String
emailAddressGen = oneof [pure correctMailAddr, arbitrary]

instance Arbitrary MailAddr where
  arbitrary = MailAddr <$> arbitrary <*> emailAddressGen

instance Arbitrary Mail where
  arbitrary = Mail <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary (CallbackConfig ()) where
  arbitrary = oneof [otherConfigGen, mailConfigGen]
    where otherConfigGen = return $ OtherConfig (const $ return ())
          mailConfigGen = MailConfig <$> arbitrary

instance Arbitrary (ScrapeConfig ()) where
  arbitrary = do
    scrapeInfoUrl' <- arbitrary
    config' <- arbitrary
    let setUrl = scrapeInfoUrl .~ scrapeInfoUrl'
    let setConfig = scrapeInfoCallbackConfig .~ config'
    return $ setUrl . setConfig $ SC.defaultScrapeConfig

instance Arbitrary a => Arbitrary (NonEmpty a) where
    arbitrary = (:|) <$> arbitrary <*> arbitrary

tMailAddr :: MailAddr
tMailAddr = MailAddr (Just "Max Mustermann") "max@mustermann.com"

correctMailAddr :: String
correctMailAddr = "correct@mail.com"

correctUrl :: String
correctUrl = "http://www.google.de"

correctMailScrapeConfig :: ScrapeConfig t
correctMailScrapeConfig = let setUrl = scrapeInfoUrl .~ correctUrl
                              setMail x = scrapeInfoCallbackConfig . _MailConfig . x .~ (tMailAddr :| [])
                              setMailFrom = setMail mailFrom
                              setMailTo = setMail mailTo 
                          in setUrl . setMailFrom . setMailTo $ SC.defaultScrapeConfig

correctOtherScrapeConfig :: ScrapeConfig ()
correctOtherScrapeConfig = let setCallbackConfig = scrapeInfoCallbackConfig .~ OtherConfig (const $ return ())
                         in setCallbackConfig SC.defaultScrapeConfig

validateScrapeConfigWithBadInfoUrlShouldNotValidate :: Assertion
validateScrapeConfigWithBadInfoUrlShouldNotValidate = 
    let wrongUrl = "httpp://www.google.de"
        scrapeInfo = scrapeInfoUrl .~ wrongUrl $ correctMailScrapeConfig 
        result = SUT.validateScrapeConfig scrapeInfo
    in  V.AccFailure [UrlProtocolInvalid] @=? result

validateScrapeConfigShouldValidateOnValidInput :: Assertion
validateScrapeConfigShouldValidateOnValidInput =
    let scrapeInfo = scrapeInfoUrl .~ correctUrl $ correctMailScrapeConfig 
        result = SUT.validateScrapeConfig scrapeInfo
    in  V.AccSuccess scrapeInfo @=? result

validateScrapeConfigWithOtherConfigShouldSatisfyAllInvariants :: ScrapeConfig () -> Property
validateScrapeConfigWithOtherConfigShouldSatisfyAllInvariants si = M.isJust (si ^? scrapeInfoCallbackConfig . _OtherConfig) ==>
  let result = SUT.validateScrapeConfig si
      p1 = property $ M.isJust (result ^? V._Success)
      badUrlErrorsOnly = (null . (L.\\ [UrlNotAbsolute, UrlProtocolInvalid])) <$> (result ^? V._Failure)
      p2 = property $ False `M.fromMaybe` badUrlErrorsOnly
  in p1 .||. p2
  
validateScrapeConfigWithMailConfigShouldSatisfyAllInvariants :: ScrapeConfig () -> Property
validateScrapeConfigWithMailConfigShouldSatisfyAllInvariants si = M.isJust (si ^? scrapeInfoCallbackConfig . _MailConfig) ==>
  let result = SUT.validateScrapeConfig si
      failure = result ^? V._Failure
      mailConfigLens = scrapeInfoCallbackConfig . _MailConfig
      (Just mailConfig) = si ^? mailConfigLens
      invalidMailAddrs t = let mailAddrs = mailConfig ^.. (t . traverse . mailAddr)
                               f = not . EmailValidate.isValid . (^. ByteStringLens.packedChars)
                           in f `L.filter` mailAddrs
      invalidMailAddrsProp es = let expected = (\errors' -> (`elem` errors') `L.all` es) <$> failure 
                                in True `M.fromMaybe` expected
      invalidMailFromAddrs = invalidMailAddrs mailFrom
      invalidMailFromAddrsProp = invalidMailAddrsProp $ MailConfigInvalidMailFromAddr <$> invalidMailFromAddrs
      invalidMailToAddrs = invalidMailAddrs mailTo
      invalidMailToAddrsProp = invalidMailAddrsProp $ MailConfigInvalidMailToAddr <$> invalidMailToAddrs
  in property invalidMailFromAddrsProp .&&. property invalidMailToAddrsProp

validateCronScheduleShouldSatisfyAllInvariants :: NCronSchedule -> Property
validateCronScheduleShouldSatisfyAllInvariants c = 
  let result = SUT.validateCronSchedule $ nCronScheduleRun c
      isCorrect = nCronScheduleRun c /= correctCronSchedule
                    || M.isJust (result ^? V._Success)
      containsExpectedError = False `M.fromMaybe` ((CronScheduleInvalid "" `elem`) <$> (result ^? V._Failure))
  in property isCorrect .||. property containsExpectedError


tests :: [TF.Test]
tests = 
  [
    testGroup "Network.ScrapeChanges.Internal"
    [
      testCase "validateScrapeConfig with bad info url should not validate"
        validateScrapeConfigWithBadInfoUrlShouldNotValidate
    , testCase "validateScrapeConfig should validate on valid input"
        validateScrapeConfigShouldValidateOnValidInput
    , testProperty "validateScrapeConfig with mail config should satisfy all invariants"
        validateScrapeConfigWithMailConfigShouldSatisfyAllInvariants
    , testProperty "validateScrapeConfig with other config should satisfy all invariants"
        validateScrapeConfigWithOtherConfigShouldSatisfyAllInvariants
    , testProperty "validateCronSchedule should satisfy all invariants"
        validateCronScheduleShouldSatisfyAllInvariants
    ]
  ]

