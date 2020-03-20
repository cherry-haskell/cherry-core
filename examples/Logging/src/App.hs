module App (app) where

import qualified Cherry.Text as Text
import qualified Cherry.Task as Task
import qualified Cherry.Program as Program
import qualified Cherry.Log as Log
import qualified Cherry.Terminal as T
import qualified Control.Concurrent
import qualified Keys
import qualified Settings
import qualified Logging
import qualified Prelude
import qualified GHC.Stack as Stack
import Cherry.Basics
import Cherry.Log
import Cherry.Text (Text)
import Cherry.Task (Task)
import Keys (Keys)


app :: Keys -> Task () ()
app keys =
  context "messages" [ ( "online", "true" ) ] <| do
    good "> hello 1"
    debug "print" "Beginning the printing." [ ( "user", "tereza" ), ( "email", "terezasokol@gmail.com" ) ]
    good "> hello 2"
    bad "> hello 3"
    Task.enter (Control.Concurrent.threadDelay 1000000)
    good "> hello 4"
    context "dying" [] <| do
      Task.enter (Prelude.error "noooo!!")
    debug "/namespace" "Last one." [ ( "user", "tereza" ), ( "email", "terezasokol@gmail.com" ) ]


good :: Stack.HasCallStack => Text -> Task () ()
good string =
  context "good" [ ( "is_ok", "true" ) ] <| do
    Task.enter (Prelude.error "what is going on!!")
    T.write (T.green ++ string ++ T.reset ++ T.newline)


bad :: Text -> Task () ()
bad string =
  context "bad" [ ( "is_ok", "false" ) ] <| do
    Task.succeed ()