{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA
-}

module Kore.Log.InfoExecutionDepth
    ( InfoExecutionDepth (..)
    , infoProofDepth
    , infoExecutionDepth
    ) where

import Prelude.Kore

import Control.Error
    ( maximumMay
    )
import Control.Monad
import Kore.Strategies.ProofState
import Log
import Numeric.Natural
    ( Natural
    )
import Pretty
    ( Pretty
    )
import qualified Pretty

data InfoExecutionDepth
    = UnprovenConfiguration ExecutionDepth
    | LongestProvenClaim ExecutionDepth
    | ExecutionLength ExecutionDepth
    deriving Show

instance Pretty InfoExecutionDepth where
    pretty (UnprovenConfiguration depth) =
        Pretty.hsep
            [ "Final execution length of an unproven configuration:"
            , Pretty.pretty (getDepth depth)
            ]
    pretty (LongestProvenClaim depth) =
        Pretty.hsep
            [ "Final execution length of the longest proven claim:"
            , Pretty.pretty (getDepth depth)
            ]
    pretty (ExecutionLength depth) =
        Pretty.hsep
            [ "Final execution length:"
            , Pretty.pretty (getDepth depth)
            ]

instance Entry InfoExecutionDepth where
    entrySeverity _ = Info
    helpDoc _ = "log execution or proof length"

infoProofDepth
    :: MonadLog log
    => [ProofState goal]
    -> log ()
infoProofDepth proofStateList =
    case depthLongestProven proofStateList of
        Just n -> logEntry (LongestProvenClaim (ExecutionDepth n))
        _ -> forM_ (depthSomeUnproven proofStateList)
            (logEntry . UnprovenConfiguration . ExecutionDepth )
  where
    depthLongestProven :: [ProofState goal] -> Maybe Natural
    depthLongestProven proofStates =
        proofStates
        & filter isProven
        & fmap (getDepth . extractDepth)
        & maximumMay

    depthSomeUnproven :: [ProofState goal] -> Maybe Natural
    depthSomeUnproven proofStates =
        proofStates
        & filter (not . isProven)
        & fmap (getDepth . extractDepth)
        & headMay

infoExecutionDepth
    :: MonadLog log
    => ExecutionDepth
    -> log ()
infoExecutionDepth depth =
    logEntry $ ExecutionLength depth