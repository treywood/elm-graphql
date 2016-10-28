module GraphQL.Query exposing (..)

import Json.Decode as Decode exposing (Decoder, (:=))


type Selection
    = FieldSelection Field
    | FragmentSpreadSelection FragmentSpread
    | InlineFragmentSelection InlineFragment


type SelectionSet
    = SelectionSet (List Selection)


type ValueSpec
    = IntSpec
    | FloatSpec
    | StringSpec
    | BooleanSpec
    | ObjectSpec SelectionSet
    | ListSpec ValueSpec
    | MaybeSpec ValueSpec


type Field
    = Field
        { name : String
        , valueSpec : ValueSpec
        , fieldAlias : Maybe String
        , args : List ( String, ArgValue )
        , directives : List Directive
        }


type FieldOption
    = FieldAlias String
    | FieldArgs (List ( String, ArgValue ))
    | FieldDirectives (List Directive)


type ArgValue
    = VariableValue String
    | IntValue Int
    | FloatValue Float
    | StringValue String
    | BooleanValue Bool
    | NullValue
    | EnumValue String
    | ListValue (List ArgValue)
    | ObjectValue (List ( String, ArgValue ))


type Directive
    = Directive
        { name : String
        , args : List ( String, ArgValue )
        }


type FragmentDefinition
    = FragmentDefinition
        { name : String
        , typeCondition : String
        , selectionSet : SelectionSet
        , directives : List Directive
        }


type FragmentSpread
    = FragmentSpread
        { name : String
        , directives : List Directive
        }


type InlineFragment
    = InlineFragment
        { typeCondition : Maybe String
        , directives : List Directive
        , selectionSet : SelectionSet
        }


type Decodable node result
    = Decodable node (Decoder result)


mapDecodable : (a -> b) -> (Decoder c -> Decoder d) -> Decodable a c -> Decodable b d
mapDecodable f g (Decodable node decoder) =
    Decodable (f node) (g decoder)


mapNode : (a -> b) -> Decodable a result -> Decodable b result
mapNode f =
    mapDecodable f identity


mapDecoder : (Decoder a -> Decoder b) -> Decodable node a -> Decodable node b
mapDecoder =
    mapDecodable identity


getNode : Decodable node result -> node
getNode (Decodable node _) =
    node


getDecoder : Decodable a result -> Decoder result
getDecoder (Decodable _ decoder) =
    decoder


variable' : String -> ArgValue
variable' =
    VariableValue


int' : Int -> ArgValue
int' =
    IntValue


float' : Float -> ArgValue
float' =
    FloatValue


string' : String -> ArgValue
string' =
    StringValue


bool' : Bool -> ArgValue
bool' =
    BooleanValue


null' : ArgValue
null' =
    NullValue


enum' : String -> ArgValue
enum' =
    StringValue


object' : List ( String, ArgValue ) -> ArgValue
object' =
    ObjectValue


list' : List ArgValue -> ArgValue
list' =
    ListValue


string : Decodable ValueSpec String
string =
    Decodable StringSpec Decode.string


int : Decodable ValueSpec Int
int =
    Decodable IntSpec Decode.int


float : Decodable ValueSpec Float
float =
    Decodable FloatSpec Decode.float


bool : Decodable ValueSpec Bool
bool =
    Decodable BooleanSpec Decode.bool


list : Decodable ValueSpec a -> Decodable ValueSpec (List a)
list =
    mapDecodable ListSpec Decode.list


construct : (a -> b) -> Decodable SelectionSet (a -> b)
construct constructor =
    Decodable (SelectionSet []) (Decode.succeed constructor)


fromObject : Decodable SelectionSet a -> Decodable ValueSpec a
fromObject =
    mapNode ObjectSpec


fieldAlias : String -> FieldOption
fieldAlias =
    FieldAlias


fieldArgs : List ( String, ArgValue ) -> FieldOption
fieldArgs =
    FieldArgs


applyFieldOption : FieldOption -> Field -> Field
applyFieldOption fieldOption (Field fieldInfo) =
    case fieldOption of
        FieldAlias name ->
            Field { fieldInfo | fieldAlias = Just name }

        FieldArgs args ->
            Field { fieldInfo | args = fieldInfo.args ++ args }

        FieldDirectives directives ->
            Field { fieldInfo | directives = fieldInfo.directives ++ directives }


addSelection : Selection -> List Selection -> List Selection
addSelection s selections =
    selections ++ [ s ]


withField :
    String
    -> List FieldOption
    -> Decodable ValueSpec a
    -> Decodable SelectionSet (a -> b)
    -> Decodable SelectionSet b
withField name fieldOptions decodableValueSpec decodableSelectionSet =
    let
        (Decodable fieldValueSpec fieldValueDecoder) =
            decodableValueSpec

        (Decodable (SelectionSet selections) objectDecoder) =
            decodableSelectionSet

        field =
            Field
                { name = name
                , valueSpec = fieldValueSpec
                , fieldAlias = Nothing
                , args = []
                , directives = []
                }
                |> flip (List.foldr applyFieldOption) fieldOptions

        selections' =
            addSelection (FieldSelection field) selections

        decoder =
            Decode.object2 (<|) objectDecoder (name := fieldValueDecoder)
    in
        Decodable (SelectionSet selections') decoder


withFragment :
    Decodable FragmentDefinition a
    -> List Directive
    -> Decodable SelectionSet (Maybe a -> b)
    -> Decodable SelectionSet b
withFragment decodableFragmentDefinition directives decodableSelectionSet =
    let
        (Decodable (FragmentDefinition fragmentDefinition) fragmentDecoder) =
            decodableFragmentDefinition

        (Decodable (SelectionSet selections) objectDecoder) =
            decodableSelectionSet

        fragmentSpread =
            FragmentSpread
                { name = fragmentDefinition.name
                , directives = directives
                }

        selections' =
            addSelection (FragmentSpreadSelection fragmentSpread) selections

        decoder =
            Decode.object2 (<|) objectDecoder (Decode.maybe fragmentDecoder)
    in
        Decodable (SelectionSet selections') decoder


withInlineFragment :
    Maybe String
    -> List Directive
    -> Decodable SelectionSet a
    -> Decodable SelectionSet (Maybe a -> b)
    -> Decodable SelectionSet b
withInlineFragment typeCondition directives decodableFragmentSelectionSet decodableParentSelectionSet =
    let
        (Decodable fragmentSelectionSet fragmentDecoder) =
            decodableFragmentSelectionSet

        (Decodable (SelectionSet selections) objectDecoder) =
            decodableParentSelectionSet

        inlineFragment =
            InlineFragment
                { typeCondition = typeCondition
                , directives = directives
                , selectionSet = fragmentSelectionSet
                }

        selections' =
            addSelection (InlineFragmentSelection inlineFragment) selections

        decoder =
            Decode.object2 (<|) objectDecoder (Decode.maybe fragmentDecoder)
    in
        Decodable (SelectionSet selections') decoder


fragment : String -> String -> List Directive -> Decodable SelectionSet a -> Decodable FragmentDefinition a
fragment name typeCondition directives =
    mapNode
        (\selectionSet ->
            FragmentDefinition
                { name = name
                , typeCondition = typeCondition
                , directives = directives
                , selectionSet = selectionSet
                }
        )