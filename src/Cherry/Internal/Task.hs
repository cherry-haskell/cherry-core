{-# LANGUAGE GADTs #-}

module Cherry.Internal.Task
  ( -- * Tasks
    Task(..), perform
  , andThen, succeed, fail, sequence
  , enter, exit
  , map, map2, map3, map4, map5, map6
  , onError, mapError

  -- * Logging
  , Output, none, terminal, custom, file, compact, verbose
  , Entry(..), Severity(..)
  , debug, info, warning, error, alert
  , onOk, onErr
  , Context, context
  ) where


-- TODO: Add json context
-- TODO: Add tracer .. is this just an output?
-- TODO: Add `attempt`

import qualified Prelude as P
import qualified Data.Text
import qualified Data.List
import qualified Data.Time.Clock as Clock
import qualified Control.Exception.Safe as Exception
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.STM.TBQueue as BQ
import qualified Control.Concurrent.MVar as MVar
import qualified GHC.Stack as Stack
import qualified Cherry.Internal.Shortcut as Shortcut
import qualified Cherry.Internal.Terminal as T
import qualified Cherry.List as List
import qualified Cherry.Debug as Debug
import qualified Cherry.Text as Text
import qualified Cherry.Result as Result
import qualified Network.HostName as HostName
import qualified System.Posix.Process as Process
import qualified System.Posix.Types as Types
import qualified System.IO
import Control.Monad (void)
import Control.Exception (bracket, bracket_)
import Prelude (IO, FilePath, (<>))
import Cherry.Basics
import Cherry.List (List)
import Cherry.Result (Result(..))
import Cherry.Maybe (Maybe(..))


newtype Task x a =
  Task { _run :: Key -> P.IO (Result x a) }


data Key = Key
  { _currentNamespace :: Text.Text
  , _currentHost :: HostName.HostName
  , _currentPID :: Types.ProcessID
  , _currentQueue :: List (BQ.TBQueue Message)
  , _currentContext :: Context
  }

data Message
  = NewEntry Entry
  | Done

instance P.Functor (Task a) where
  fmap func task =
    Task <| \key ->
      let onResult result =
            case result of
              Ok a -> Ok (func a)
              Err x -> Err x
      in
      _run task key
        |> P.fmap onResult


instance P.Applicative (Task a) where
  pure a =
    succeed a

  (<*>) func task =
    Task <| \key ->
      let onResult resultFunc resultTask =
            case (resultFunc, resultTask) of
              ( Ok func_, Ok task_ ) ->
                Ok (func_ task_)

              ( Err x, _ ) ->
                Err x

              ( _, Err x ) ->
                Err x
      in do
      func_ <- _run func key
      task_ <- _run task key
      P.return (onResult func_ task_)


instance P.Monad (Task a) where
  task >>= func =
    Task <| \key ->
      let onResult result =
            case result of
              Ok ok ->
                _run (func ok) key

              Err err ->
                P.return (Err err)
      in
      _run task key
        |> Shortcut.andThen onResult



-- BASICS


perform :: List Output -> Task x a -> IO (Result x a)
perform outputs task = do
  host <- HostName.getHostName
  pId <- Process.getProcessID
  let emptyKey = Key "" host pId [] []

  ( queues, quiters ) <-
      outputs
        |> List.map (toQueueAndQuit emptyKey)
        |> P.sequence
        |> P.fmap List.unzip

  let init :: IO Key
      init =
        P.return (Key "" host pId queues [])

  let exit :: Key -> IO ()
      exit _ = do
        _ <- P.sequence quiters
        P.return ()

  bracket init exit (_run task)


toQueueAndQuit :: Key -> Output -> IO ( BQ.TBQueue Message, IO () )
toQueueAndQuit emptyKey (Output settings) = do
  resource <- (_open settings)
  let write = (_write settings) resource
  let close = (_close settings) resource

  queue <- STM.atomically (BQ.newTBQueue 4096)
  worker <- spawnWorker write queue

  let quit = do
        _ <- STM.atomically (BQ.writeTBQueue queue Done)
        _ <- Async.waitCatch worker
        _ <- close
        P.return ()

  P.return ( queue, quit )


spawnWorker :: (Entry -> IO ()) -> BQ.TBQueue Message -> IO (Async.Async ())
spawnWorker write queue =
  let loop = do
        next <- STM.atomically (BQ.readTBQueue queue)
        case next of
          NewEntry entry -> do
            _ <- Exception.tryAny (write entry)
            loop

          Done ->
            P.return ()
  in do
  Async.async loop


succeed :: a -> Task x a
succeed a =
  Task <| \_ -> P.return (Ok a)


fail :: x -> Task x a
fail x =
  Task <| \_ -> P.return (Err x)



-- MAPS


map :: (a -> b) -> Task x a -> Task x b
map =
  Shortcut.map


map2 :: (a -> b -> result) -> Task x a -> Task x b -> Task x result
map2 =
  Shortcut.map2


map3 :: (a -> b -> c -> result) -> Task x a -> Task x b -> Task x c -> Task x result
map3 =
  Shortcut.map3


map4 :: (a -> b -> c -> d -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x result
map4 =
  Shortcut.map4


map5 :: (a -> b -> c -> d -> e -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x e -> Task x result
map5 =
  Shortcut.map5


map6 :: (a -> b -> c -> d -> e -> f -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x e -> Task x f -> Task x result
map6 =
  Shortcut.map6


andThen :: (a -> Task x b) -> Task x a -> Task x b
andThen =
  Shortcut.andThen


sequence :: List (Task x a) -> Task x (List a)
sequence tasks =
  List.foldr (map2 (:)) (succeed []) tasks


onError :: (x -> Task y a) -> Task x a -> Task y a
onError func task =
  Task <| \key ->
    let onResult result =
          case result of
            Ok ok -> P.return (Ok ok)
            Err err -> _run (func err) key
    in
    _run task key
      |> Shortcut.andThen onResult


mapError :: (x -> y) -> Task x a -> Task y a
mapError func task =
  task |> onError (fail << func)



-- INTEROP


enter :: IO (Result x a) -> Task x a
enter io =
  Task <| \_ -> io


exit :: Task x a -> IO (Result x a)
exit =
  perform [none]



-- LOGGING


data Output where
  Output :: OutputSettings x resource -> Output


data OutputSettings x resource =
  OutputSettings
    { _open :: IO resource
    , _write :: resource -> Entry -> IO ()
    , _close :: resource -> IO ()
    }


none :: Output
none =
  Output <| OutputSettings
    { _open = P.return ()
    , _write = \_ _ -> P.return ()
    , _close = \_ -> P.return ()
    }


terminal :: Output
terminal =
  let write entry =
        T.message (color entry) (title entry) (_namespace entry)
          [ _message entry
          , "For context:"
          , contexts entry
          ]

      color entry =
        case _severity entry of
          Debug -> T.cyan
          Info -> T.cyan
          Warning -> T.yellow
          Error -> T.magenta
          Alert -> T.red

      title entry =
        case _severity entry of
          Debug -> "Debug"
          Info -> "Info"
          Warning -> "Warning"
          Error -> "Error"
          Alert -> "Alert"

      contexts entry =
        List.map context (_contexts entry)
          |> List.append [T.indent 4 <> "time: " <> Data.Text.pack (P.show (_time entry)) ]
          |> Text.join T.newline

      context ( name, value ) = do
        T.indent 4 <> name <> ": " <> value
  in
  Output <| OutputSettings
    { _open = P.return ()
    , _write = \_ -> write
    , _close = \_ -> P.return ()
    }


file :: FilePath -> Output
file filepath =
  Output <| OutputSettings
    { _open = do
        handle <- System.IO.openFile filepath System.IO.AppendMode
        System.IO.hSetBuffering handle System.IO.LineBuffering
        lock <- MVar.newMVar ()
        P.return ( handle, lock )

    , _write = \( handle, lock ) _ -> do
        bracket_ (MVar.takeMVar lock) (MVar.putMVar lock ()) <|
          System.IO.hPutStrLn handle "Debug.toString entry"

    , _close = \( handle, lock ) -> do
        System.IO.hFlush handle
        System.IO.hClose handle
    }


custom :: Task x r -> (r -> Entry -> Task x ()) -> (r -> Task x ()) -> Output
custom open write close =
  Output <| OutputSettings
    { _open = do
        result <- exit open
        case result of
          Ok resource -> P.return resource
          Err _ -> P.error "Could not initiate logger."
    , _write = \r e -> exit (write r e) |> void
    , _close = \r -> exit (close r) |> void
    }



-- LOG ENTRY


debug :: Stack.HasCallStack => Text.Text -> Text.Text -> Context -> Task e ()
debug =
  log Debug


info :: Stack.HasCallStack => Text.Text -> Text.Text -> Context -> Task e ()
info =
  log Info


warning :: Stack.HasCallStack => Text.Text -> Text.Text -> Context -> Task e ()
warning =
  log Warning


error :: Stack.HasCallStack => Text.Text -> Text.Text -> Context -> Task e ()
error =
  log Error


alert :: Stack.HasCallStack => Text.Text -> Text.Text -> Context -> Task e ()
alert =
  log Alert



data Verbosity
  = Compact
  | Verbose


verbose :: Verbosity
verbose =
  Verbose


compact :: Verbosity
compact =
  Compact


{-| -}
onOk :: (a -> Task () ()) -> Task x a -> Task x a
onOk log task =
  Task <| \key -> do
    result <- _run task key
    case result of
      Ok ok -> do
        _ <- _run (log ok) key
        P.return ()

      Err _ ->
        P.return ()

    P.return result


{-| -}
onErr :: (x -> Task () ()) -> Task x a -> Task x a
onErr log task =
  Task <| \key -> do
    result <- _run task key
    case result of
      Ok _ ->
        P.return ()

      Err err -> do
        _ <- _run (log err) key
        P.return ()

    P.return result


context :: Text.Text -> Context -> Task x a -> Task x a
context namespace context task =
  Task <| \key ->
    let nextKey = Key
          { _currentNamespace = _currentNamespace key <> namespace
          , _currentContext = _currentContext key ++ context
          , _currentHost = _currentHost key
          , _currentPID = _currentPID key
          , _currentQueue = _currentQueue key
          }
    in
    _run task nextKey


data Entry = Entry
  { _severity :: Severity
  , _namespace :: Text.Text
  , _message :: Text.Text
  , _time :: Clock.UTCTime
  , _contexts :: Context
  }


data Severity
  = Debug
  | Info
  | Warning
  | Error
  | Alert


type Context =
  List ( Text.Text, Text.Text )



-- INTERNAL


log :: Severity -> Text.Text -> Text.Text -> Context -> Task x ()
log severity namespace message context =
  Task <| \key -> do
    time <- Clock.getCurrentTime
    let entry = merge key (Entry severity namespace message time context)
    _currentQueue key
      |> List.map (addToQueue entry)
      |> List.map STM.atomically
      |> P.sequence
    P.return (Ok ())


addToQueue :: Entry -> BQ.TBQueue Message -> STM.STM Bool
addToQueue entry queue = do
  full <- BQ.isFullTBQueue queue
  if full then
    P.return (not full)
  else do
    BQ.writeTBQueue queue (NewEntry entry)
    P.return (not full)


merge :: Key -> Entry -> Entry
merge key entry =
  Entry
    { _severity = _severity entry
    , _namespace = _currentNamespace key <> _namespace entry
    , _message = _message entry
    , _contexts = _currentContext key ++ _contexts entry
    , _time = _time entry
    }
