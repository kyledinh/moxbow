----------------------------------------------------------------------
--
-- Types.elm
-- Moxbow shared types
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module Moxbow.Types exposing ( Node, nodeVersion, emptyNode
                              , ContentType (..)
                              , Plist, get, set
                              , State(..)
                              , Backend
                              , UploadType(..)
                              , BackendOperation(..)
                              , BackendError(..), BackendResult, BackendWrapper
                              , stateDict, backendDict, operationDict
                              , updateState, updateStateFromResult
                              , operate, downloadFile
                              , uploadTypeToString, settingsPath, uploadPath
                              , backendErrorToString
                              )

import HtmlTemplate.Types exposing ( Atom(..) )

import Time exposing ( Time )
import Dict exposing ( Dict )

nodeVersion : Int
nodeVersion =
    1

type alias Node msg =
    { version : Int             --nodeVersion
    , comment : String          --visible only to editor
    , pageTemplate : String
    , nodeTemplate : String
    , title : String
    , path : String
    , author : String
    , time : Time
    , indices : Dict String String -- tag -> index
    , contentType : ContentType
    , rawContent : String
    , content : Atom msg
    , plist : Plist --on backend. All properties saved.
    }

emptyNode : Node msg
emptyNode =
    { version = nodeVersion
    , comment = ""
    , pageTemplate = "page"
    , nodeTemplate = "node"
    , title = "Untitled"
    , path = "nada"
    , author = "Unknown"
    , time = -433540800000 + (8 * 3600 * 1000)
    , indices = Dict.empty
    , contentType = Markdown
    , rawContent = "You were expecting maybe a treatise?"
    , content = ListAtom []
    , plist = []
    }

type ContentType
    = Json
    | Markdown
    | Text
    | Code

type alias XPlist a =
    List (String, a)

type alias Plist =
    XPlist String

get : String -> XPlist a -> Maybe a
get key plist =
    case plist of
        [] ->
            Nothing
        (k, v) :: rest ->
            if key == k then
                Just v
            else
                get key rest

set : String -> a -> XPlist a -> XPlist a
set key value plist =
    (key, value) :: (List.filter (\(k,_) -> k /= key) plist)

type UploadType
    = Settings
    | Page
    | Template
    | Image

uploadTypeToString : UploadType -> String
uploadTypeToString uploadType =
    case uploadType of
        Settings -> "settings"
        Page -> "page"
        Template -> "template"
        Image -> "image"

settingsPath : String
settingsPath =
    "settings.json"

uploadPath : UploadType -> String -> String
uploadPath uploadType path =
    case uploadType of
        Settings ->
            settingsPath
        _ ->
            (uploadTypeToString uploadType) ++ "/" ++ path
            
type State
    = NullState
    | DictState (Dict String String)

type BackendOperation
    = DownloadFile State UploadType String (Maybe String)

type BackendError
    = AuthorizationError
    | NotFoundError
    | OtherBackendError String

backendErrorToString : BackendError -> BackendOperation -> String
backendErrorToString err operation =
    case err of
        AuthorizationError ->
            "Authorization error"
        NotFoundError ->
            let path = case operation of
                          DownloadFile _ uploadType name _ ->
                              uploadPath uploadType name

            in
                "File not found: " ++ path
        OtherBackendError string ->
            string

-- Backends promise not to change their state if an operation
-- returns an error
type alias BackendResult =
    Result (BackendError, BackendOperation) BackendOperation

type alias BackendWrapper msg =
    BackendResult -> msg

type alias Backend msg =
    { name : String
    , description : String
    , operator : BackendWrapper msg -> BackendOperation -> Cmd msg
    , state : State
    }

stateDict : State -> Dict String String
stateDict state =
    case state of
        DictState dict ->
            dict
        _ ->
            Dict.empty

backendDict : Backend msg -> Dict String String
backendDict backend =
    stateDict backend.state

operationState : BackendOperation -> State
operationState operation =
    case operation of
        DownloadFile state _ _ _ ->
            state

operationDict : BackendOperation -> Dict String String
operationDict operation =
    stateDict <| operationState operation

updateState : BackendOperation -> Backend msg -> Backend msg
updateState operation backend =
    { backend | state = operationState operation }

updateStateFromResult : BackendResult -> Backend msg -> Backend msg
updateStateFromResult result backend =
    updateState
        (case result of
             Err (_, operation) -> operation
             Ok operation -> operation
        )
        backend

operate : Backend msg -> BackendWrapper msg -> BackendOperation -> Cmd msg
operate backend wrapper operation =
    let operator = backend.operator
    in
        operator wrapper operation

downloadFile : Backend msg -> BackendWrapper msg -> UploadType -> String -> Cmd msg
downloadFile backend wrapper uploadType path =
    operate backend wrapper
        <| DownloadFile backend.state uploadType path Nothing
