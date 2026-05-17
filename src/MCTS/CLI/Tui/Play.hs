{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 7.4: interactive `brick` TUI for `mcts play`. The board
-- renders via `MCTS.CLI.Tui.Board.renderBoard`; the event loop
-- accepts legacy-notation move input via `MCTS.Notation.parseMove`,
-- applies it, then advances the AI through
-- `MCTS.Search.UCT.uctSearch`. The in-app commands `:hint`, `:undo`,
-- `:save`, `:quit` are dispatched per
-- [DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint 7.4](../../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md).
module MCTS.CLI.Tui.Play
    ( runInteractivePlay
    , PlayState (..)
    , initialPlayState
    , applyUserInput
    , UserInputOutcome (..)
    ) where

import qualified Brick.AttrMap as A
import Brick.Main (App (..), defaultMain, halt, neverShowCursor)
import Brick.Types (BrickEvent (..), EventM, Widget)
import Brick.Util (fg)
import Brick.Widgets.Border (border)
import Brick.Widgets.Core (str, vBox, withAttr)
import Control.Monad.State.Strict (get, modify, put)
import Data.Word (Word16, Word64)
import qualified Graphics.Vty as V

import MCTS.CLI.Tui.Board (renderBoard, renderStatus)
import MCTS.Engine
    ( Board
    , applyMove
    , initialBoard
    , legalMoves
    , terminalWinner
    )
import MCTS.Notation (parseMove, renderMove)
import MCTS.Rng.Mix (mix)
import MCTS.Search.UCT (uctSearch)
import MCTS.Types (Action, Winner (..))

data PlayState = PlayState
    { playStateBoard :: !Board
    , playStateHistory :: ![Board]
    -- ^ Snapshots before each played move; head is most-recent.
    , playStateMoveCount :: !Int
    , playStateSeed :: !Word64
    , playStateMaxPlies :: !Word16
    , playStateSims :: !Int
    , playStateMessage :: !String
    , playStateInput :: !String
    -- ^ Current text buffer being typed (between user keystrokes).
    , playStateLastHint :: !(Maybe Action)
    , playStateDone :: !(Maybe Winner)
    }

initialPlayState :: Word64 -> Word16 -> Int -> PlayState
initialPlayState seed maxPlies sims =
    PlayState
        { playStateBoard = initialBoard
        , playStateHistory = []
        , playStateMoveCount = 0
        , playStateSeed = seed
        , playStateMaxPlies = maxPlies
        , playStateSims = sims
        , playStateMessage = "type *(x,y) / H(x,y) / V(x,y) and Enter; :hint :undo :quit"
        , playStateInput = ""
        , playStateLastHint = Nothing
        , playStateDone = Nothing
        }

-- | Outcome of dispatching a single text line.
data UserInputOutcome
    = OutcomeQuit
    | OutcomeContinue !PlayState

-- | Pure dispatcher for one input line. Returns either `OutcomeQuit`
-- to terminate the event loop, or `OutcomeContinue` with an updated
-- `PlayState`. Pure so it can be unit-tested.
applyUserInput :: String -> PlayState -> UserInputOutcome
applyUserInput raw st =
    case dropWhile (== ' ') raw of
        "" -> OutcomeContinue st{playStateInput = ""}
        ":quit" -> OutcomeQuit
        ":q" -> OutcomeQuit
        ":hint" -> OutcomeContinue (issueHint st)
        ":undo" -> OutcomeContinue (issueUndo st)
        ":save" ->
            OutcomeContinue
                st
                    { playStateMessage = ":save is a CLI side effect; use mcts inspect show later"
                    , playStateInput = ""
                    }
        other -> OutcomeContinue (applyMoveText other st)

applyMoveText :: String -> PlayState -> PlayState
applyMoveText raw st =
    case parseMove raw of
        Nothing ->
            st
                { playStateInput = ""
                , playStateMessage = "InvalidMove: could not parse `" <> raw <> "`"
                }
        Just action ->
            if action `elem` legalMoves (playStateBoard st)
                then
                    let nextBoard = applyMove action (playStateBoard st)
                        terminal = terminalWinner (playStateMaxPlies st) nextBoard
                     in st
                            { playStateBoard = nextBoard
                            , playStateHistory = playStateBoard st : playStateHistory st
                            , playStateMoveCount = playStateMoveCount st + 1
                            , playStateInput = ""
                            , playStateLastHint = Nothing
                            , playStateMessage = "applied " <> renderMove action
                            , playStateDone = settleTerminal nextBoard terminal
                            }
                else
                    st
                        { playStateInput = ""
                        , playStateMessage = "InvalidMove: " <> renderMove action <> " is not legal here"
                        }

settleTerminal :: Board -> Maybe Winner -> Maybe Winner
settleTerminal board terminal =
    case terminal of
        Just w -> Just w
        Nothing
            | null (legalMoves board) -> Just Draw
            | otherwise -> Nothing

issueHint :: PlayState -> PlayState
issueHint st =
    let board = playStateBoard st
        seed = mix (playStateSeed st) (fromIntegral (playStateMoveCount st))
        sims = playStateSims st
        maxPlies = fromIntegral (playStateMaxPlies st)
        (chosen, _) = uctSearch board seed sims maxPlies
     in st
            { playStateLastHint = Just chosen
            , playStateInput = ""
            , playStateMessage = "hint: " <> renderMove chosen
            }

issueUndo :: PlayState -> PlayState
issueUndo st =
    case playStateHistory st of
        [] -> st{playStateInput = "", playStateMessage = "nothing to undo"}
        (prev : rest) ->
            st
                { playStateBoard = prev
                , playStateHistory = rest
                , playStateMoveCount = max 0 (playStateMoveCount st - 1)
                , playStateDone = Nothing
                , playStateLastHint = Nothing
                , playStateInput = ""
                , playStateMessage = "undid one move"
                }

drawUi :: PlayState -> [Widget String]
drawUi st =
    [ vBox
        [ border (renderBoard (playStateBoard st))
        , border $
            renderStatus
                "play"
                (playStateMoveCount st)
                (fromIntegral (playStateMaxPlies st))
        , withAttr (A.attrName "message") (str (playStateMessage st))
        , str ("> " <> playStateInput st)
        , case playStateLastHint st of
            Nothing -> str ""
            Just hint -> withAttr (A.attrName "hint") (str ("hint: " <> renderMove hint))
        , case playStateDone st of
            Nothing -> str ""
            Just winner -> withAttr (A.attrName "winner") (str ("Game over: " <> show winner))
        ]
    ]

handleEvent :: BrickEvent String () -> EventM String PlayState ()
handleEvent (VtyEvent (V.EvKey key _mods)) =
    case key of
        V.KEsc -> halt
        V.KEnter -> do
            st <- get
            case applyUserInput (playStateInput st) st of
                OutcomeQuit -> halt
                OutcomeContinue st' -> do
                    put st'
                    case playStateDone st' of
                        Nothing -> advanceAi
                        Just _ -> pure ()
        V.KChar ' ' -> do
            st <- get
            -- Space when buffer is empty advances AI as a smoke shortcut;
            -- otherwise treated as literal whitespace in the input.
            if null (playStateInput st)
                then advanceAi
                else modify $ \s -> s{playStateInput = playStateInput s <> " "}
        V.KChar ch -> modify $ \s -> s{playStateInput = playStateInput s <> [ch]}
        V.KBS -> modify $ \s -> s{playStateInput = dropLast (playStateInput s)}
        V.KDel -> modify $ \s -> s{playStateInput = ""}
        _ -> pure ()
handleEvent _ = pure ()

dropLast :: [a] -> [a]
dropLast [] = []
dropLast xs = init xs

advanceAi :: EventM String PlayState ()
advanceAi = do
    st <- get
    case playStateDone st of
        Just _ -> pure ()
        Nothing -> do
            let board = playStateBoard st
                seed = mix (playStateSeed st) (fromIntegral (playStateMoveCount st))
                sims = playStateSims st
                maxPlies = fromIntegral (playStateMaxPlies st)
                (chosen, _visits) = uctSearch board seed sims maxPlies
                nextBoard = applyMove chosen board
                terminal = terminalWinner (playStateMaxPlies st) nextBoard
            modify $ \s ->
                s
                    { playStateBoard = nextBoard
                    , playStateHistory = playStateBoard s : playStateHistory s
                    , playStateMoveCount = playStateMoveCount s + 1
                    , playStateMessage = "AI played " <> renderMove chosen
                    , playStateLastHint = Nothing
                    , playStateDone = settleTerminal nextBoard terminal
                    }

playApp :: App PlayState () String
playApp =
    App
        { appDraw = drawUi
        , appChooseCursor = neverShowCursor
        , appHandleEvent = handleEvent
        , appStartEvent = pure ()
        , appAttrMap =
            const
                ( A.attrMap
                    V.defAttr
                    [ (A.attrName "winner", fg V.yellow)
                    , (A.attrName "hint", fg V.cyan)
                    , (A.attrName "message", fg V.white)
                    ]
                )
        }

-- | Run the interactive brick event loop. The current move advance
-- always runs the in-process Haskell engine UCT search; the foreign
-- backend dispatch is owned by Sprint 7.4's remaining work.
runInteractivePlay :: Word64 -> Word16 -> Int -> IO PlayState
runInteractivePlay seed maxPlies sims =
    defaultMain playApp (initialPlayState seed maxPlies sims)
