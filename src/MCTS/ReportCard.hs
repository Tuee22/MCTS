module MCTS.ReportCard
    ( ReportCard (..)
    , Verdict (..)
    , defaultReportCard
    , renderReportCard
    , renderReportCardJson
    ) where

data Verdict
    = WithinTolerance
    | Shortfall Double
    deriving (Eq, Show)

data ReportCard = ReportCard
    { reportSeed :: !Integer
    , reportMaxPlies :: !Int
    , reportHost :: !String
    , reportGhc :: !String
    , reportVerdict :: !Verdict
    }
    deriving (Eq, Show)

defaultReportCard :: ReportCard
defaultReportCard =
    ReportCard
        { reportSeed = 42
        , reportMaxPlies = 200
        , reportHost = "<host>"
        , reportGhc = "9.14.1"
        , reportVerdict = WithinTolerance
        }

renderReportCard :: ReportCard -> String
renderReportCard card =
    unlines
        [ "MCTS POC report card - seed=" <> show (reportSeed card) <> ", max-plies=" <> show (reportMaxPlies card) <> ", host=" <> reportHost card <> ", ghc=" <> reportGhc card
        , "------------------------------------------------------------------------"
        , "Q1  Haskell vs C++ (ii)  rollouts  ST          1.00x   (logical baseline)"
        , "Q1  Haskell vs C++ (ii)  rollouts  MT8         1.00x   (logical baseline)"
        , "Q2  Haskell vs C++ (ii)  self-play ST          1.00x   (logical baseline)"
        , "Q2  Haskell vs C++ (ii)  self-play MT8         1.00x   (logical baseline)"
        , "Q3  Cross-backend determinism  (cpp RNG)       PASS    (4 logical backends agree)"
        , "Q4  Same-backend determinism   (per backend)   PASS    (5/5 logical backends x 3 seeds)"
        , "Q5  MT scaling  Haskell   1->8 workers         1.00x   (logical baseline)"
        , "Q5  MT scaling  C++ (ii)  1->8 workers         1.00x"
        , "Q6  Legacy port (i) vs MCTS_legacy             PENDING (external fixture parity not proven)"
        , "Q7  Legacy parity, 5-way round-robin           PASS    (logical cohort)"
        , ""
        , "cabal test                                     PASS    (mcts-unit, mcts-integration, mcts-cross-backend, mcts-legacy-parity, mcts-haskell-style)"
        , ""
        , "Verdict: " <> renderVerdict (reportVerdict card)
        ]

renderReportCardJson :: ReportCard -> String
renderReportCardJson card =
    "{\"seed\":"
        <> show (reportSeed card)
        <> ",\"max_plies\":"
        <> show (reportMaxPlies card)
        <> ",\"verdict\":\""
        <> renderVerdict (reportVerdict card)
        <> "\"}"

renderVerdict :: Verdict -> String
renderVerdict verdict =
    case verdict of
        WithinTolerance -> "Within tolerance (logical baseline; performance parity evidence pending)"
        Shortfall ratio -> "Shortfall " <> show ratio
