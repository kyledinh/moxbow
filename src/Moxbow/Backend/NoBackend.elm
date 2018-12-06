----------------------------------------------------------------------
--
-- NoBackend.elm
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module Moxbow.Backend.NoBackend exposing ( backend )

import Moxbow.Types exposing ( State(..), UploadType(..)
                              , BackendOperation(..)
                              , BackendError(..), BackendWrapper, Backend
                              , uploadTypeToString, settingsPath, uploadPath
                              )

import Http
import Debug exposing ( log )
import Base64
import Task

state : State
state =
    NullState

backend : Backend msg
backend =
    { name = "NoBackend"
    , description = "Stub to make code work."
    , operator = operate
    , state = state
    }

-- Wipe out all options, default to do nothing
operate : BackendWrapper msg -> BackendOperation -> Cmd msg
operate wrapper operation =
    case operation of
        DownloadFile _ uploadType path _ ->
            downloadFile wrapper operation uploadType path

fetchUrl : String -> ((Result Http.Error String) -> msg) -> Cmd msg
fetchUrl url wrapper =
    Http.send wrapper <| httpGetString (log "Getting URL" url)

httpGetString : String -> Http.Request String
httpGetString url =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Cache-control" "no-cache" ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectString
        , timeout = Nothing
        , withCredentials = False
        }

toBackendError : Http.Error -> BackendError
toBackendError error =
    case error of
        Http.BadStatus response ->
            let code = response.status.code
            in
                if code == 401 then
                    AuthorizationError
                else if code == 404 then
                    NotFoundError
                else
                    OtherBackendError <| toString error
        _ ->
            OtherBackendError <| toString error

downloadFile : BackendWrapper msg -> BackendOperation -> UploadType -> String -> Cmd msg
downloadFile wrapper operation uploadType path =
    let url = uploadPath uploadType path
        wrap = (\res ->
                    case res of
                        Err err ->
                            wrapper
                            <| Err (toBackendError err, operation)
                        Ok string ->
                            wrapper
                            <| Ok (DownloadFile state uploadType path <| Just string)
               )
    in
        fetchUrl url wrap

httpWrapper : BackendOperation -> BackendWrapper msg -> Result Http.Error String -> msg
httpWrapper operation wrapper result =
    wrapper <|
        case result of
            Err err ->
                Err (toBackendError err, operation)
            Ok ok ->
                if String.trim ok == "OK" then
                    Ok operation
                else
                    Err (OtherBackendError <| "Backend error: " ++ ok, operation)
