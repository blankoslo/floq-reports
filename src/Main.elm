port module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.App as Html
import Html.Events exposing (onClick, on, targetValue, onInput)
import Http
import Json.Decode as Json
import Json.Decode exposing ((:=))
import String
import Char exposing (isLower, isUpper)
import List
import Task
import Date exposing (..)
import Date.Extra.Format exposing (isoDateString)

port fetchFile : (String, String, String) -> Cmd msg

months : List Month
months = [Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec]

monthToInt : Month -> Int
monthToInt month =
    case month of
        Jan -> 1
        Feb -> 2
        Mar -> 3
        Apr -> 4
        May -> 5
        Jun -> 6
        Jul -> 7
        Aug -> 8
        Sep -> 9
        Oct -> 10
        Nov -> 11
        Dec -> 12

monthToString : Month -> String
monthToString month =
    case month of
        Jan -> "Januar"
        Feb -> "Februar"
        Mar -> "Mars"
        Apr -> "April"
        May -> "Mai"
        Jun -> "Juni"
        Jul -> "Juli"
        Aug -> "August"
        Sep -> "September"
        Oct -> "Okober"
        Nov -> "November"
        Dec -> "Desember"

intDecoder : Json.Decoder Int
intDecoder =
  targetValue `Json.andThen` \val ->
    case String.toInt val of
      Ok i -> Json.succeed i
      Err err -> Json.fail err

type alias Flags = { token : String, apiUrl : String }

main : Program Flags
main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

type alias DateString = String

-- MODEL
type alias Project =
  { id : String
  , name : String
  , customer: String
  }

type alias StatusRange =
  { start : DateString
  , end : DateString
  }

type alias Model =
  { projects : List Project
  , statusRange : StatusRange
  , year : Int
  , month : Int
  , token : String
  , apiUrl : String
  }

init : Flags -> (Model, Cmd Msg)
init flags =
    let initialRange = StatusRange "1970-01-01" "1970-01-01"
        initialModel =  Model [] initialRange 1970 1 flags.token flags.apiUrl
    in
        (initialModel, Task.perform Initialize Initialize Date.now)

-- UPDATE
type Msg
  = FetchSucceed (List Project)
  | FetchFail Http.Error
  | Initialize Date.Date
  | YearChanged Int
  | MonthChanged Int
  | RangeStartDate String
  | RangeEndDate String
  | DateMissing
  | DownloadFile String String String


update : Msg -> Model -> (Model, Cmd Msg)
update action model =
  case action of
    Initialize date ->
        let month = (monthToInt (Date.month date) - 1) % 12
            year = if month == 1
                   then Date.year date - 1
                   else Date.year date
        in
          ({ model |
                 statusRange = StatusRange (isoDateString date) (isoDateString date),
                 year = year,
                 month = month
           }, getProjects model.token model.apiUrl)

    FetchSucceed projects ->
      ({ model | projects = projects }, Cmd.none)

    FetchFail _ ->
      (model, Cmd.none)

    YearChanged year ->
        ({ model | year = year }, Cmd.none)

    MonthChanged month ->
        ({ model | month = month }, Cmd.none)

    RangeStartDate start ->
        let oldRange = model.statusRange
            newRange = { oldRange | start = start }
        in
            ({ model | statusRange = newRange }, Cmd.none)
    RangeEndDate end ->
        let oldRange = model.statusRange
            newRange = { oldRange | end = end }
        in
            ({ model | statusRange = newRange }, Cmd.none)
    DateMissing ->
        (model, Cmd.none)

    DownloadFile url jwt filename ->
      (model, fetchFile (url, jwt, filename))

-- VIEW
view : Model -> Html Msg
view model =
  div [] [status model, projects model]

status : Model -> Html Msg
status model =
    let url = model.apiUrl
              ++ "/reporting/time_tracking_status"
              ++ "?start_date=" ++ model.statusRange.start
              ++ "&end_date=" ++ model.statusRange.end
        jwt = Http.uriDecode model.token
        filename = "status-" ++ model.statusRange.start ++ "–" ++ model.statusRange.end
    in
      div []
          [ h3 [] [text "Timeføringstatus"]
          , div [class "mdl-grid"]
            [ div [class "mdl-cell mdl-cell--3-col mdl-cell--6-col-phone"]
                [label [for "start"] [ text "Startdato" ]
                , input [id "start", type' "date" , class "form-control", onInput RangeStartDate, value model.statusRange.start] []
                ]
            , div [class "mdl-cell mdl-cell--3-col mdl-cell--6-col-phone"]
                [label [for "end"] [ text "Sluttdato (inklusiv)" ]
                , input [id "end", type' "date" , class "form-control", onInput RangeEndDate, value model.statusRange.end] []
                ]
            ]
          , div [class "mdl-grid"]
              [div [class "mdl-cell mdl-cell--2-col mdl-cell--6-col-phone"]
                 [a [onClick (DownloadFile url jwt filename)] [text "Hent rapport"]]

              ]
          ]

projects : Model -> Html Msg
projects model =
  let toListItem p =
          let url = model.apiUrl
                    ++ "/reporting/hours/" ++ p.id
                    ++ "?year=" ++ toString model.year
                    ++ "&month=" ++ toString model.month
              jwt = Http.uriDecode model.token
              month = if model.month < 10
                      then "0" ++ toString model.month
                      else toString model.month
              filename = toString model.year ++ "-"
                         ++ month ++ "-"
                         ++ String.filter (\c -> isUpper c || isLower c) p.name
                         ++ ".csv"
          in
          li
            [class "mdl-list__item"]
            [a
              [onClick (DownloadFile url jwt filename)]
              [span [class "code"] [text p.id], text (": " ++ p.customer ++ " – " ++ p.name)]]
      items = (List.map toListItem model.projects)
      toMonthOption m = option
                     [selected (monthToInt m == model.month), value (toString (monthToInt m))]
                     [text (monthToString m)]
      monthOptions = List.map toMonthOption months
      toYearOption y = option
                         [selected (y == model.year), value (toString y)]
                         [text (toString y)]
      yearOptions = List.map toYearOption [2015..2025]
  in
  div []
    [ h3 [] [text "Prosjekter"]
    , div [class "mdl-grid"]
      [ div [class "mdl-cell mdl-cell--2-col mdl-cell--6-col-phone"]
        [ select [on "change" (Json.map MonthChanged intDecoder)] monthOptions
        ]
      , div [class "mdl-cell mdl-cell--2-col mdl-cell--6-col-phone"]
        [ select [on "change" (Json.map YearChanged intDecoder)] yearOptions
        ]
      ]
    , div []
      [ ul [class "mdl-list"] items]
    ]


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none

-- HTTP
getProjects : String -> String -> Cmd Msg
getProjects token apiUrl =
  let url = apiUrl ++ "/reporting/projects"
      request =
        { verb = "GET"
        , headers = [("Authorization", "Bearer " ++ token)]
        , url = url
        , body = Http.empty
        }
  in Task.perform FetchFail FetchSucceed (Http.fromJson decodeProject (Http.send Http.defaultSettings request))

decodeProject : Json.Decoder (List Project)
decodeProject =
  Json.list (Json.object3 Project ("projectId" := Json.string) ("projectName" := Json.string) ("customerName" := Json.string))
