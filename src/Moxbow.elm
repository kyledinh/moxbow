----------------------------------------------------------------------
--
-- Moxbow.elm
-- Blogging in Elm
-- Distributed under the MIT License
-- See LICENSE.txt
--
----------------------------------------------------------------------

module Moxbow exposing (..)

import Moxbow.Types as Types
    exposing ( Node, ContentType(..), emptyNode
             , State(..), BackendWrapper, Backend
             , BackendOperation, UploadType(..)
             , BackendResult, updateStateFromResult
             )
import Moxbow.Parsers exposing ( parseNode, parseNodeContent )
import Moxbow.Backend.NoBackend as NoBackend

import HtmlTemplate exposing ( makeLoaders, insertFunctions, insertMessages
                             , insertStringMessages
                             , addPageProcessors
                             , getExtra, setExtra, getDicts
                             , addOutstandingPagesAndTemplates
                             , loadPage, receiveCustomPage
                             , loadTemplate, receiveTemplate
                             , loadOutstandingPageOrTemplate
                             , maybeLoadOutstandingPageOrTemplate
                             , getPage, setPage, removePage
                             , getTemplate
                             , getAtom, setAtom, setAtoms, getDictsAtom
                             , clearPages
                             , render, eval, cantFuncall
                             )

import HtmlTemplate.Types exposing ( Loaders, Atom(..), Dicts(..) )

import HtmlTemplate.EncodeDecode
    exposing ( decodeAtom, encodeAtom, customEncodeAtom )

import HtmlTemplate.Markdown as Markdown

import HtmlTemplate.Utility as Utility exposing ( mergeStrings )

import HtmlTemplate.PlayDiv exposing ( PlayState, emptyPlayState
                                     , playDivFunction
                                     , Update, playStringUpdate, updatePlayState
                                     )

import Html exposing ( Html, Attribute
                     , div, p, text, a, textarea, pre
                     )
import Html.Attributes as Attributes exposing ( style, href, rows, cols, class
                                              , type_, value )
import Html.Events exposing ( onClick, onInput )
import Http
import Date
import Time exposing ( Time, second )
import Dict exposing ( Dict )
import List.Extra as LE

import Navigation exposing ( Location )

log = Debug.log

main =
    Navigation.program
        Navigate
        { init = init
        , update = update
        , view = view
        , subscriptions = (\x -> Time.every second Tick)
        }

type StartupState
    = JustStarted
    | BackendInstalled
    | Ready

type alias Model =
    { loaders: Loaders Msg Extra
    , location : Location
    , page: Maybe String
    , pendingPage : Maybe String
    , playState : Maybe (PlayState Msg)
    , backend : Backend Msg
    , startupState : StartupState
    , time : Time
    , error : Maybe String
    }

templateDirs : List String
templateDirs =
    [ "default", "black", "red" ]

settingsFile : String
settingsFile =
    "settings"

settingsPageName : String
settingsPageName =
    "_settings"

indexTemplate : String
indexTemplate =
    "index"

pageTemplate : String
pageTemplate =
    "page"

nodeTemplate : String
nodeTemplate =
    "node"

initialTemplates : List String
initialTemplates =
    [ pageTemplate, indexTemplate, nodeTemplate ]

indexPage : String
indexPage =
    "index"

initialPages : List String
initialPages =
    [ ]

postTemplate : String
postTemplate =
    "post"

templateFileType : String
templateFileType =
    ".json"

templateFilename : String -> String
templateFilename name =
    name ++ templateFileType

pageFileType : String
pageFileType =
    ".txt"

pageFilename : String -> String
pageFilename name =
    name ++ pageFileType

gotoPageMessage : List (Atom Msg) -> d -> Msg
gotoPageMessage args _ =
    case args of
        [StringAtom page] ->
            GotoPage page
        _ ->
            SetError <| "Can't go to page: " ++ (toString args)

setMessage : List (Atom Msg) -> d -> (String -> Msg)
setMessage args _ =
    case args of
        [StringAtom name] ->
            SetMsg name
        _ ->
            (\_ ->
                 SetError <| "Can't set value: " ++ (toString args)
            )

messages : List (String, List (Atom Msg) -> Dicts Msg -> Msg)
messages =
    [ ( "gotoPage", gotoPageMessage )
    ]

stringMessages : List (String, List (Atom Msg) -> Dicts Msg -> (String -> Msg))
stringMessages =
    [ ( "set", setMessage )
    , ( "setText", setTextMessage )
    , ( "setText", setTextMessage )
    ]

pageLinkFunction : List (Atom Msg) -> d -> Atom Msg
pageLinkFunction args _ =
    case normalizePageLinkArgs args of
        Just ( page, title ) ->
            HtmlAtom
            <| a [ href <| "#" ++ page
                 --, onClick <| GotoPage page
                 ]
                [ text title ]
        _ ->
            cantFuncall "pageLink" args

emailLinkFunction : List (Atom Msg) -> d -> Atom Msg
emailLinkFunction args _ =
    case args of
        [ StringAtom email ] ->
            HtmlAtom
            <| a [ href <| "mailto:" ++ email
                 ]
                [ text email ]
        _ ->
            cantFuncall "mailLink" args

normalizePageLinkArgs : List (Atom Msg) -> Maybe (String, String)
normalizePageLinkArgs atom =
    case atom of
        [ StringAtom page ] ->
            Just (page, page)
        [ StringAtom page, StringAtom title ] ->
            Just (page, title)
        _ ->
            Nothing

xossbowFunction : List (Atom Msg) -> d -> Atom Msg
xossbowFunction args _ =
    HtmlAtom
    <| a [ href <| "/" ]
        [ text "Xossbow" ]

emptyString : Atom msg
emptyString =
    StringAtom ""

getFunction : List (Atom Msg) -> Dicts Msg -> Atom Msg
getFunction args dicts =
    case args of
        [ StringAtom name ] ->
            Maybe.withDefault emptyString <|  getDictsAtom name dicts
        _ ->
            emptyString

record : String -> List (String, Atom Msg) -> List (Atom Msg) -> Atom Msg
record tag attributes body =
    RecordAtom
        { tag = tag
        , attributes = attributes
        , body = body
        }

funcall : String -> List (Atom Msg) -> Atom Msg
funcall function args =
    FuncallAtom
        { function = function
        , args = args
        }

textInputFunction : List (Atom Msg) -> Dicts Msg -> Atom Msg
textInputFunction args dicts =
    case args of
        [ PListAtom attributes, StringAtom name ] ->
            record "input"
                (List.append
                     [ ("type", StringAtom "text")
                     , ("onInput"
                       , funcall "setText" [ StringAtom name ]
                       )
                     , ("value"
                       , funcall "getText" [ StringAtom name ]
                       )
                     ]
                    attributes
                )
                []
        _ ->
            cantFuncall "textInput" args

setTextMessage : List (Atom Msg) -> d -> (String -> Msg)
setTextMessage args dicts =
    case args of
        [ StringAtom name ] ->
            SetText name
        _ ->
            (\_ -> SetError <| "Can't set value: " ++ (toString args))

formText : String
formText =
    "<formText>"

setText : String -> Atom Msg -> Loaders Msg x -> Loaders Msg x
setText name value loaders =
    let plist = case getAtom formText loaders of
                    Just (PListAtom res) ->
                        Types.set name value res
                    _ ->
                        [(name, value)]
    in
        setAtom formText (PListAtom plist) loaders

getText : String -> Dicts Msg -> Atom Msg
getText name dicts =
    case getDictsAtom formText dicts of
        Just (PListAtom plist) ->
            case Types.get name plist of
                Just res ->
                    res
                Nothing ->
                    emptyString
        _ ->
            emptyString

getTextFunction : List (Atom Msg) -> Dicts Msg -> Atom Msg
getTextFunction args dicts =
    case args of
        [ StringAtom name ] ->
            getText name dicts
        _ ->
            cantFuncall "getText" args

textInputRowFunction : List (Atom Msg) -> Dicts Msg -> Atom Msg
textInputRowFunction args dicts =
    case args of
        [ StringAtom title, StringAtom name, IntAtom size ] ->
            record "tr"
                []
                [ record "th"
                      []
                      [ StringAtom title ]
                , record "td"
                    []
                    [ textInputFunction
                          [ PListAtom [("size", IntAtom size)]
                          , StringAtom name
                          ]
                          dicts
                    ]
                ]
        _ ->
            cantFuncall "textInputRow" args

textValueRowFunction : List (Atom Msg) -> Dicts Msg -> Atom Msg
textValueRowFunction args dicts =
    case args of
        [ StringAtom title, StringAtom name ] ->
            record "tr"
                []
                [ record "th"
                      []
                      [ StringAtom title ]
                , record "td"
                    []
                    [ funcall "getText" [StringAtom name] ]
                ]
        _ ->
            cantFuncall "textInputRow" args

formSelectorFunction : List (Atom Msg) -> d -> Atom Msg
formSelectorFunction args _ =
    case args of
        [ StringAtom name, ListAtom options, StringAtom selection ] ->
            record "select"
                [ ("onInput", funcall "setText" [StringAtom name])
                ] <|
                List.map (\(value) ->
                    let s = case value of
                                StringAtom string -> string
                                _ -> toString value
                    in
                        record "option"
                            [ ("value", StringAtom s)
                            , ("selected", BoolAtom (selection == s))
                            ]
                            [value]
                    )
                    options
        _ ->
            cantFuncall "formSelector" args

functions : List (String, List (Atom Msg) -> Dicts Msg -> Atom Msg)
functions =
    [ ( "pageLink", pageLinkFunction )
    , ( "emailLink", emailLinkFunction )
    , ( "xossbow", xossbowFunction )
    , ( "get", getFunction )
    , ( "textInput", textInputFunction )
    , ( "getText", getTextFunction )
    , ( "textInputRow", textInputRowFunction )
    , ( "textValueRow", textValueRowFunction )
    , ( "formSelector", formSelectorFunction )
    ]

type alias Extra =
    { templateDir : String
    , backend : Backend Msg
    }

makeInitialExtra : Backend Msg -> Extra
makeInitialExtra backend =
    { templateDir = "default"
    , backend = backend
    }

pageProcessors : List (String, String -> Atom Msg -> Loaders Msg Extra -> Loaders Msg Extra)
pageProcessors =
    [ ( settingsPageName, installSettings )
    , ( "", add_page_Property )
    ]

makeInitialLoaders : Backend Msg -> Loaders Msg Extra
makeInitialLoaders backend =
    makeLoaders fetchTemplate fetchPage (makeInitialExtra backend)
    |> setAtom "referer" (StringAtom indexPage)
    |> insertFunctions functions
    |> insertMessages messages
    |> insertStringMessages stringMessages
    |> addPageProcessors pageProcessors
    |> addOutstandingPagesAndTemplates [settingsPageName] []

---
--- init
---

init : Location -> ( Model, Cmd Msg)
init location =
    let backend = defaultBackend
        model = { loaders = makeInitialLoaders backend
                , location = location
                , page = Nothing
                , pendingPage = Nothing
                , playState = Nothing
                , backend = backend
                , startupState = JustStarted
                , time = 0
                , error = Nothing
                }
    in
        ( model
        , loadOutstandingPageOrTemplate model.loaders
        )

-- Store just-loaded "settings" plist as an atom, and remove it as a page.
-- The pages reference it as "$settings.<property>".
installSettings : String -> Atom Msg -> Loaders Msg Extra -> Loaders Msg Extra
installSettings name settings loaders =
    setAtom settingsFile settings
        <| removePage name loaders

-- The value of most pages is a plist processed by the "node" template.
-- This adds the page's own name to its plist when it's loaded.
add_page_Property : String -> Atom Msg -> Loaders Msg Extra -> Loaders Msg Extra
add_page_Property name page loaders =
    case page of
        PListAtom plist ->
          setPage name (PListAtom <| ("page", StringAtom name) :: plist) loaders
        _ ->
          loaders

type Msg
    = TemplateFetchDone String (Loaders Msg Extra) BackendResult
    | PageFetchDone String (Loaders Msg Extra) BackendResult
    | GotoPage String
    | UpdatePlayState Update
    | SetError String
    | Navigate Location
    | Tick Time
    | SetMsg String String
    | SetText String String

templateDir : Loaders Msg Extra -> String
templateDir loaders =
    .templateDir <| getExtra loaders

loadersBackend : Loaders Msg Extra -> Backend Msg
loadersBackend loaders =
    .backend <| getExtra loaders

fetchTemplate : String -> Loaders Msg Extra -> Cmd Msg
fetchTemplate name loaders =
    let filename = templateFilename name
        path = (templateDir loaders) ++ "/" ++ filename
    in
        Types.downloadFile (loadersBackend loaders)
            (TemplateFetchDone name loaders)
            Template path

fetchPage : String -> Loaders Msg Extra -> Cmd Msg
fetchPage name loaders =
    let uploadType = if name == settingsPageName then
                         Settings
                     else
                         Page
        path = if uploadType == Page then
                   (pageFilename name)
               else
                   ""
    in
        Types.downloadFile (loadersBackend loaders)
            (PageFetchDone name loaders)
            uploadType path

---
--- update
---

updateBackend : BackendResult -> Model -> Model
updateBackend result model =
    { model | backend = updateStateFromResult result model.backend }

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TemplateFetchDone name loaders result ->
            templateFetchDone name loaders result
                <| updateBackend result model
        PageFetchDone name loaders result ->
            pageFetchDone name loaders result
                <| updateBackend result model
        GotoPage page ->
            gotoPage page model
        UpdatePlayState update ->
            updatePlayString update model
        SetError message ->
            ( { model | error = Just message }
            , Cmd.none
            )
        Tick time ->
            ( { model | time = time }
            , Cmd.none
            )
        Navigate location ->
            navigate location model
        SetMsg name value ->
            ( { model | loaders = setAtom name (StringAtom value) model.loaders }
            , Cmd.none
            )
        SetText name value ->
            ( { model | loaders = setText name (StringAtom value) model.loaders }
            , Cmd.none
            )

pageFromLocation : Location -> String
pageFromLocation location =
    let hash = location.hash
        sansSharp = if (String.left 1 hash) == "#" then
                        String.dropLeft 1 hash
                    else
                        hash
    in
        case String.split "." sansSharp of
            [] ->
                indexPage
            res :: _ ->
                if res == "" then
                    indexPage
                else
                    res

navigate : Location -> Model -> ( Model, Cmd Msg )
navigate location model =
    let newPage = pageFromLocation location
        mod = { model | location = location }
    in
        if case model.page of
               Nothing ->
                   True
               Just page ->
                   page /= newPage
        then
            gotoPage newPage mod
        else
            ( mod
            , Cmd.none
            )

gotoPage : String -> Model -> ( Model, Cmd Msg )
gotoPage page model =
    let m = { model | error = Nothing
            , pendingPage = Just page
            }
    in
        ( m
        , fetchPage page <| clearPages model.loaders
        )

templateFetchDone : String -> Loaders Msg Extra -> BackendResult -> Model -> ( Model, Cmd Msg )
templateFetchDone name loaders result model =
    case result of
        Err (err, _) ->
            continueLoading
                loaders
                { model
                    | error =
                      Just
                      <| "Error fetching template " ++ name ++ ": " ++
                          (toString err)
                }
        Ok (Types.DownloadFile _ _ _ (Just json)) ->
            case receiveTemplate name json loaders of
                Err msg ->
                    continueLoading
                        loaders
                        { model
                            | error =
                                Just
                                <| "While parsing template \"" ++
                                    name ++ "\": " ++ msg
                        }
                Ok loaders2 ->
                    continueLoading loaders2 model
        x ->
            continueLoading
                loaders
                { model
                    | error = Just ("Don't understand result: " ++ (toString x))
                }

continueLoading : Loaders Msg Extra -> Model -> ( Model, Cmd Msg )
continueLoading loaders model =
    case maybeLoadOutstandingPageOrTemplate loaders of
        Just cmd ->
            -- Do NOT update model.loaders yet, or the screen flashes
            ( model, cmd )
        Nothing ->
            let m = { model | loaders = loaders }
            in
                case m.pendingPage of
                    Nothing ->
                        -- This happens at startup
                        gotoPage (pageFromLocation m.location) m
                    Just page ->
                        ( { m |
                            page = Just page
                          , pendingPage = Nothing
                          , loaders = case m.page of
                                          Nothing -> loaders
                                          Just referer ->
                                              setAtom
                                                "referer"
                                                (StringAtom referer)
                                                loaders
                          }
                        , Cmd.none
                        )

parsePage : String -> String -> Result String (Atom Msg)
parsePage page text =
    if page == settingsPageName then
        decodeAtom text
    else
        let node = case parseNode text of
                       Err err ->
                           { emptyNode
                               | title = "Error parsing page: " ++ page
                               , path = page
                               , contentType = Text
                               , rawContent = text
                           }
                       Ok n ->
                           n
        in
            nodeToAtom { node | path = page }

nodeToAtom : Node msg -> Result String (Atom msg)
nodeToAtom node =
    case parseNodeContent node of
        Err s as err ->
            err
        Ok atom ->
            let plist : List (String, Atom msg)
                plist = [ ("title", StringAtom node.title)
                        , ("path", StringAtom node.path)
                        , ("author", StringAtom node.author)
                        , ("time", FloatAtom node.time)
                        -- This should be formatted according to a setting
                        -- using justinmimbs/elm-date-extra
                        , ("date", StringAtom <| toString <| Date.fromTime node.time)
                        , ("content", atom)
                        ]
            in
                Ok
                <| FuncallAtom
                    { function = "let"
                    , args = [ PListAtom [ ("node", PListAtom plist) ]
                             , LookupTemplateAtom node.nodeTemplate
                             ]
                    }

getStringProp : String -> List (String, Atom msg) -> Maybe String
getStringProp prop plist =
    case LE.find (\(key, _) -> prop == key) plist of
        Just (_, StringAtom res) -> Just res
        _ -> Nothing

pageFetchDone : String -> Loaders Msg Extra -> BackendResult -> Model -> ( Model, Cmd Msg )
pageFetchDone name loaders result model =
    case result of
        Err (err, _) ->
            continueLoading
                loaders
                { model
                    | error =
                        Just
                        <| "Error fetching page " ++ name ++ ": " ++
                            (toString err)
                }
        Ok (Types.DownloadFile _ _ _ (Just text)) ->
            let pageres = parsePage name text
                settings = getAtom settingsFile loaders
            in
                case receiveCustomPage (\_ -> pageres) name text loaders of
                    Err msg ->
                        case model.startupState of
                            BackendInstalled ->
                                -- No settings.json on new backend.
                                -- Stay with the original
                                backendInstalled loaders model
                            _ ->
                                continueLoading
                                    loaders
                                    { model
                                        | error =
                                          Just
                                          <| ("While loading page \""
                                              ++ name ++ "\": " ++ msg)
                                    }
                    Ok loaders2 ->
                        case model.startupState of
                            Ready ->
                                continueLoading loaders2 model
                            JustStarted ->
                                maybeRefetchSettings pageres loaders2 model
                            BackendInstalled ->
                                backendInstalled loaders2 model
        Ok x ->
            continueLoading
                loaders
                { model
                    | error = Just ("Don't understand result: " ++ (toString x))
                }

backendInstalled : Loaders Msg Extra -> Model -> ( Model, Cmd Msg )
backendInstalled loaders model =
    let loaders2 = addOutstandingPagesAndTemplates
                   initialPages initialTemplates loaders
    in
        continueLoading
            loaders2 { model | startupState = Ready }

maybeRefetchSettings : Result String (Atom msg) -> Loaders Msg Extra -> Model -> (Model, Cmd Msg)
maybeRefetchSettings pageres loaders model =
    case pageres of
        Err err ->
            continueLoading
                loaders
                { model
                    | error
                      = Just <| "Error loading initial settings: " ++ err
                }
        Ok (PListAtom plist) ->
            case getStringProp "backend" plist of
                Nothing ->
                    backendInstalled
                        loaders
                        { model
                            | error
                              = Just "---"
                        }
                Just backendName ->
                    backendInstalled
                        loaders
                        { model
                            | error
                              = Just "+++"
                        }

        Ok x ->
            continueLoading
                loaders
                { model
                    | error
                      = Just <| "Non-plist for settings: " ++ (toString x)
                }

maxOneLineEncodeLength : Int
maxOneLineEncodeLength = 60

encode : Atom msg -> String
encode atom =
    let res = customEncodeAtom 0 atom
    in
        if String.length res <= maxOneLineEncodeLength then
            res
        else
            encodeAtom atom

getPlayState : Model -> PlayState Msg
getPlayState model =
    case model.playState of
        Nothing ->
            updatePlayState
                (playStringUpdate "\"Hello Xossbow!\"")
                model.loaders
                emptyPlayState
        Just playState ->
            playState

updatePlayString : Update -> Model -> ( Model, Cmd Msg )
updatePlayString update model =
    ( { model
          | playState
              = Just
                <| updatePlayState update model.loaders <| getPlayState model
      }
    , Cmd.none
    )

defaultBackend : Backend msg
defaultBackend =
    NoBackend.backend


---
--- view
---

view : Model -> Html Msg
view model =
    div []
        [ case model.page of
              Nothing ->
                  text ""
              Just page ->
                  let loaders = insertFunctions
                                [ ( "playDiv"
                                  , playDivFunction
                                      UpdatePlayState <| getPlayState model
                                  )
                                ]
                                model.loaders
                      template = pageTemplate
                      content = LookupPageAtom page
                  in
                      case getTemplate template loaders of
                          Nothing ->
                              dictsDiv "Template" template loaders
                          Just tmpl ->
                              case getPage page loaders of
                                  Nothing ->
                                      dictsDiv "Page" page loaders
                                  Just atom ->
                                      let loaders2 = setAtoms
                                                     [ ("content", content)
                                                     , ("page", StringAtom page)
                                                     ]
                                                     loaders
                                      in
                                          render tmpl loaders2
        , p [ style [ ( "color", "red" ) ] ]
              [ case model.error of
                    Just err ->
                    text err
                    Nothing ->
                    text " "
              ]
        ]

dictsDiv : String -> String -> Loaders Msg Extra -> Html Msg
dictsDiv thing page loaders =
    div []
        [ p [] [ text <| thing ++ " not found: " ++ page ]
        , p []
              [ a [ href "template/" ]
                    [ text "template/"]
              ]
        , p []
            [ text "dicts:"
            , br
            , text <| toString <| getDicts loaders ]
        ]

br : Html Msg
br =
    Html.br [] []
