%%%-------------------------------------------------------------------
%%% @author Karl Anderson <karl@2600hz.org>
%%% @copyright (C) 2011, Karl Anderson
%%% @doc
%%%
%%% @end
%%% Created : 19 Mar 2011 by Karl Anderson <karl@2600hz.org>
%%%-------------------------------------------------------------------
-module(cf_call_command).

-include("callflow.hrl").

-export([audio_macro/2, flush_dtmf/1, find_callerid/2]).
-export([answer/1, hangup/1]).
-export([bridge/2, bridge/3, bridge/4, bridge/5, bridge/6, bridge/7]).
-export([play/2, play/3]).
-export([record/2, record/3, record/4, record/5, record/6]).
-export([store/3, store/4, store/5]).
-export([tones/2]).
-export([play_and_collect_digit/2]).
-export([play_and_collect_digits/4, play_and_collect_digits/5, play_and_collect_digits/6,
         play_and_collect_digits/7, play_and_collect_digits/8, play_and_collect_digits/9]).
-export([say/2, say/3, say/4, say/5]).
-export([conference/2, conference/3, conference/4, conference/5]).
-export([noop/1]).
-export([flush/1]).

-export([b_answer/1, b_hangup/1]).
-export([b_bridge/2, b_bridge/3, b_bridge/4, b_bridge/5, b_bridge/6, b_bridge/7]).
-export([b_play/2, b_play/3]).
-export([b_record/2, b_record/3, b_record/4, b_record/5, b_record/6]).
-export([b_play_and_collect_digit/2]).
-export([b_play_and_collect_digits/4, b_play_and_collect_digits/5, b_play_and_collect_digits/6,
         b_play_and_collect_digits/7, b_play_and_collect_digits/8, b_play_and_collect_digits/9]).
-export([b_conference/2, b_conference/3, b_conference/4, b_conference/5]).
-export([b_noop/1]).

-export([wait_for_message/1, wait_for_message/2, wait_for_message/3, wait_for_message/4]).
-export([wait_for_bridge/1, wait_for_unbridge/0]).
-export([wait_for_dtmf/1]).
-export([wait_for_application_or_dtmf/2]).
-export([wait_for_hangup/0]).
-export([send_callctrl/2]).

%%--------------------------------------------------------------------
%% @pubic
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec(audio_macro/2 :: (Commands :: proplist(), Call :: #cf_call{}) -> ok).
-spec(audio_macro/3 :: (Commands :: proplist(), Call :: #cf_call{}, Queue :: json_objects()) -> ok).

audio_macro(Commands, Call) ->
    audio_macro(Commands, Call, []).
audio_macro([], #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call, Queue) ->
    Command = [
                {<<"Application-Name">>, <<"queue">>}
               ,{<<"Commands">>, Queue}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:queue_req(Command),
    send_callctrl(Payload, Call);
audio_macro([{play, MediaName}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, play_command(MediaName, ?ANY_DIGIT, Call)}|Queue]);
audio_macro([{play, MediaName, Terminators}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, play_command(MediaName, Terminators, Call)}|Queue]);
audio_macro([{say, Say}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, say_command(Say, <<"name_spelled">>, <<"pronounced">>, <<"en">>, Call)}|Queue]);
audio_macro([{say, Say, Type}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, say_command(Say, Type, <<"pronounced">>, <<"en">>, Call)}|Queue]);
audio_macro([{say, Say, Type, Method}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, say_command(Say, Type, Method, <<"en">>, Call)}|Queue]);
audio_macro([{say, Say, Type, Method, Language}|T], Call, Queue) ->
    audio_macro(T, Call, [{struct, say_command(Say, Type, Method, Language, Call)}|Queue]);
audio_macro([{tones, Tones}|T], Call, Queue) ->
    audio_macro(T, Call, [ tones_command(Tones, Call)|Queue]).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec(flush_dtmf/1 :: (Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
flush_dtmf(Call) ->
    b_play(<<"silence_stream://250">>, Call).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to answer the channel
%% @end
%%--------------------------------------------------------------------
-spec(answer/1 :: (Call :: #cf_call{}) -> ok).
-spec(b_answer/1 :: (Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).

answer(#cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    Command = [
                {<<"Application-Name">>, <<"answer">>}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:answer_req(Command),
    send_callctrl(Payload, Call).

b_answer(Call) ->
    answer(Call),
    wait_for_message(<<"answer">>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to hangup the channel.
%% This request will execute immediately
%% @end
%%--------------------------------------------------------------------
-spec(hangup/1 :: (Call :: #cf_call{}) -> ok).
-spec(b_hangup/1 :: (Call :: #cf_call{}) -> tuple(ok, channel_hungup) | tuple(error, execution_failure)).

hangup(#cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    Command = [
                {<<"Application-Name">>, <<"hangup">>}
               ,{<<"Insert-At">>, <<"now">>}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:hangup_req(Command),
    send_callctrl(Payload, Call).

b_hangup(Call) ->
    hangup(Call),
    wait_for_hangup().

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to bridge the call
%% @end
%%--------------------------------------------------------------------
-spec(bridge/2 :: (Endpoints :: json_objects(), Call :: #cf_call{}) -> ok).
-spec(bridge/3 :: (Endpoints :: json_objects(), Timeout :: binary(), Call :: #cf_call{}) -> ok).
-spec(bridge/4 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Call :: #cf_call{}) -> ok).
-spec(bridge/5 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), Call :: #cf_call{}) -> ok).
-spec(bridge/6 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), ContinueOnFail :: binary(), Call :: #cf_call{}) -> ok).
-spec(bridge/7 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), ContinueOnFail :: binary(), Ringback :: binary(), Call :: #cf_call{}) -> ok).

-spec(b_bridge/2 :: (Endpoints :: json_objects(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).
-spec(b_bridge/3 :: (Endpoints :: json_objects(), Timeout :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).
-spec(b_bridge/4 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).
-spec(b_bridge/5 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), Call :: #cf_call{}) ->
                         tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).
-spec(b_bridge/6 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), ContinueOnFail :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).
-spec(b_bridge/7 :: (Endpoints :: json_objects(), Timeout :: binary(), CIDType :: binary(), Strategy :: binary(), ContinueOnFail :: binary(), Ringback :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, bridge_failed | channel_hungup | execution_failed | timeout)).

bridge(Endpoints, Call) ->
    bridge(Endpoints, <<"26">>, Call).
bridge(Endpoints, Timeout, Call) ->
    bridge(Endpoints, Timeout, <<"default">>, Call).
bridge(Endpoints, Timeout, CIDType, Call) ->
    bridge(Endpoints, Timeout, CIDType, <<"single">>, Call).
bridge(Endpoints, Timeout, CIDType, Strategy, Call) ->
    bridge(Endpoints, Timeout, CIDType, Strategy, <<"true">>, Call).
bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, Call) ->
    bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, <<"us-ring">>, Call).
bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, Ringback, #cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    {CIDNum, CIDName} = find_callerid(CIDType, Call),
    Command = [
                {<<"Application-Name">>, <<"bridge">>}
               ,{<<"Endpoints">>, Endpoints}
               ,{<<"Timeout">>, Timeout}
               ,{<<"Continue-On-Fail">>, ContinueOnFail}
               ,{<<"Outgoing-Caller-ID-Name">>, CIDName}
               ,{<<"Outgoing-Caller-ID-Number">>, CIDNum}
               ,{<<"Ringback">>, Ringback}
               ,{<<"Dial-Endpoint-Method">>, Strategy}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
            ],
    {ok, Payload} = whistle_api:bridge_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

b_bridge(Endpoints, Call) ->
    b_bridge(Endpoints, <<"26">>, Call).
b_bridge(Endpoints, Timeout, Call) ->
    b_bridge(Endpoints, Timeout, <<"default">>, Call).
b_bridge(Endpoints, Timeout, CIDType, Call) ->
    b_bridge(Endpoints, Timeout, CIDType, <<"single">>, Call).
b_bridge(Endpoints, Timeout, CIDType, Strategy, Call) ->
    b_bridge(Endpoints, Timeout, CIDType, Strategy, <<"true">>, Call).
b_bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, Call) ->
    b_bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, <<"us-ring">>, Call).
b_bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, Ringback, Call) ->
    bridge(Endpoints, Timeout, CIDType, Strategy, ContinueOnFail, Ringback, Call),
    wait_for_bridge((whistle_util:to_integer(Timeout)*1000) + 5000).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to play media to the
%% caller.  A list of terminators can be provided that the caller
%% can use to skip playback.
%% @end
%%--------------------------------------------------------------------
-spec(play/2 :: (Media :: binary(), Call :: #cf_call{}) -> ok).
-spec(play/3 :: (Media :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> ok).

-spec(b_play/2 :: (Media :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_play/3 :: (Media :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).

play(Media, Call) ->
    play(Media, ?ANY_DIGIT, Call).
play(Media, Terminators, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"play">>}
               ,{<<"Media-Name">>, Media}
               ,{<<"Terminators">>, Terminators}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:play_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

b_play(Media, Call) ->
    b_play(Media, ?ANY_DIGIT, Call).
b_play(Media, Terminators, Call) ->
    play(Media, Terminators, Call),
    wait_for_message(<<"play">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"call_event">>, false).

play_command(Media, Terminators, #cf_call{call_id=CallId}) ->
    [
      {<<"Application-Name">>, <<"play">>}
     ,{<<"Media-Name">>, Media}
     ,{<<"Terminators">>, Terminators}
     ,{<<"Call-ID">>, CallId}
    ].

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to record a file.
%% A list of keys can be used as the terminator or a silence threshold.
%% @end
%%--------------------------------------------------------------------
-spec(record/2 :: (MediaName :: binary(), Call :: #cf_call{}) -> ok).
-spec(record/3 :: (MediaName :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> ok).
-spec(record/4 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), Call :: #cf_call{}) -> ok).
-spec(record/5 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), SilenceThreshold :: binary(), Call :: #cf_call{}) -> ok).
-spec(record/6 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), SilenceThreshold :: binary(), SilenceHits :: binary(), Call :: #cf_call{}) -> ok).

-spec(b_record/2 :: (MediaName :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_record/3 :: (MediaName :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_record/4 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_record/5 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), SilenceThreshold :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_record/6 :: (MediaName :: binary(), Terminators :: list(binary()), TimeLimit :: binary(), SilenceThreshold :: binary(), SilenceHits :: binary(), Call :: #cf_call{}) ->
			 tuple(ok, json_object()) | tuple(error, atom())).

record(MediaName, Call) ->
    record(MediaName, ?ANY_DIGIT, Call).
record(MediaName, Terminators, Call) ->
    record(MediaName, Terminators, <<"120">>, Call).
record(MediaName, Terminators, TimeLimit, Call) ->
    record(MediaName, Terminators, TimeLimit, <<"200">>,  Call).
record(MediaName, Terminators, TimeLimit, SilenceThreshold, Call) ->
    record(MediaName, Terminators, TimeLimit, SilenceThreshold, <<"3">>, Call).
record(MediaName, Terminators, TimeLimit, SilenceThreshold, SilenceHits, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"record">>}
               ,{<<"Media-Name">>, MediaName}
               ,{<<"Terminators">>, Terminators}
               ,{<<"Time-Limit">>, TimeLimit}
               ,{<<"Silence-Threshold">>, SilenceThreshold}
               ,{<<"Silence-Hits">>, SilenceHits}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:record_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

b_record(MediaName, Call) ->
    b_record(MediaName, ?ANY_DIGIT, Call).
b_record(MediaName, Terminators, Call) ->
    b_record(MediaName, Terminators, <<"120">>, Call).
b_record(MediaName, Terminators, TimeLimit, Call) ->
    b_record(MediaName, Terminators, TimeLimit, <<"200">>,  Call).
b_record(MediaName, Terminators, TimeLimit, SilenceThreshold, Call) ->
    b_record(MediaName, Terminators, TimeLimit, SilenceThreshold, <<"3">>, Call).
b_record(MediaName, Terminators, TimeLimit, SilenceThreshold, SilenceHits, Call) ->
    record(MediaName, Terminators, TimeLimit, SilenceThreshold, SilenceHits, Call),
    wait_for_message(<<"record">>, <<"RECORD_STOP">>, <<"call_event">>, false).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to store the file
%% @end
%%--------------------------------------------------------------------
-spec(store/3 :: (MediaName :: binary(), Transfer :: binary(), Call :: #cf_call{}) -> ok).
-spec(store/4 :: (MediaName :: binary(), Transfer :: binary(), Method :: binary(), Call :: #cf_call{}) -> ok).
-spec(store/5 :: (MediaName :: binary(), Transfer :: binary(), Method :: binary(), Headers :: json_objects(), Call :: #cf_call{}) -> ok).

store(MediaName, Transfer, Call) ->
    store(MediaName, Transfer, <<"put">>, Call).
store(MediaName, Transfer, Method, Call) ->
    store(MediaName, Transfer, Method, [?EMPTY_JSON_OBJECT], Call).
store(MediaName, Transfer, Method, Headers, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"store">>}
               ,{<<"Media-Name">>, MediaName}
               ,{<<"Media-Transfer-Method">>, Method}
               ,{<<"Media-Transfer-Destination">>, Transfer}
               ,{<<"Additional-Headers">>, Headers}
               ,{<<"Insert-At">>, <<"now">>}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:store_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to play tones to the
%% caller
%% @end
%%--------------------------------------------------------------------
-spec(tones/2 :: (Tones :: json_objects(), Call :: #cf_call{}) -> ok).

tones(Tones, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"tones">>}
               ,{<<"Tones">>, Tones}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:tones_req(Command),
    send_callctrl(Payload, Call).

-spec(tones_command/2 :: (Tones :: list(integer()), Call :: #cf_call{}) -> json_object()).
tones_command(Tones, #cf_call{call_id=CallId}) ->
    {struct, [
	      {<<"Application-Name">>, <<"tones">>}
	      ,{<<"Tones">>, Tones}
	      ,{<<"Call-ID">>, CallId}
	     ]}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to play media to a
%% caller, and collect a number of DTMF events.
%% @end
%%--------------------------------------------------------------------
-spec(play_and_collect_digit/2 :: (Media :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/4 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/5 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/6 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/7 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/8 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Regex :: binary(), Call :: #cf_call{}) -> ok).
-spec(play_and_collect_digits/9 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Regex :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> ok).

-spec(b_play_and_collect_digit/2 :: (Media :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/4 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/5 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/6 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/7 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/8 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Regex :: binary(), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).
-spec(b_play_and_collect_digits/9 :: (MinDigits :: binary(), MaxDigits :: binary(), Media :: binary(), Tries :: binary(), Timeout :: binary(), MediaInvalid :: binary(), Regex :: binary(), Terminators :: list(binary()), Call :: #cf_call{}) -> tuple(ok, binary()) | tuple(error, atom())).

play_and_collect_digit(Media, Call) ->
    play_and_collect_digits(<<"1">>, <<"1">>, Media, Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, <<"3">>,  Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, <<"3000">>, Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, <<"silence_stream://250">>, Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, <<"\\d+">>, Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, [<<"#">>], Call).
play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, Terminators, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"play_and_collect_digits">>}
               ,{<<"Minimum-Digits">>, MinDigits}
               ,{<<"Maximum-Digits">>, MaxDigits}
               ,{<<"Timeout">>, Timeout}
               ,{<<"Terminators">>, Terminators}
               ,{<<"Media-Name">>, Media}
               ,{<<"Media-Tries">>, Tries}
               ,{<<"Failed-Media-Name">>, MediaInvalid}
               ,{<<"Digits-Regex">>, Regex}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:play_collect_digits_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

b_play_and_collect_digit(Media, Call) ->
    b_play_and_collect_digits(<<"1">>, <<"1">>, Media, Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Call) ->
    b_play_and_collect_digits(MinDigits, MaxDigits, Media, <<"3">>,  Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Call) ->
    b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, <<"3000">>, Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, Call) ->
    b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, <<"silence_stream://250">>, Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Call) ->
    b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, <<"\\d+">>, Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, Call) ->
    b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, [<<"#">>], Call).
b_play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, Terminators, Call) ->
    play_and_collect_digits(MinDigits, MaxDigits, Media, Tries, Timeout, MediaInvalid, Regex, Terminators, Call),
    Wait = (whistle_util:to_integer(Timeout) * whistle_util:to_integer(Tries)) + 5000,
    case wait_for_message(<<"play_and_collect_digits">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"call_event">>, Wait) of
        {ok, JObj} ->
            {ok, wh_json:get_value(<<"Application-Response">>, JObj, <<>>)};
        {error, _}=E ->
            E
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to say text to a caller
%% @end
%%--------------------------------------------------------------------
-spec(say/2 :: (Say :: binary(), Call :: #cf_call{}) -> ok).
-spec(say/3 :: (Say :: binary(), Type :: binary(), Call :: #cf_call{}) -> ok).
-spec(say/4 :: (Say :: binary(), Type :: binary(), Method :: binary(), Call :: #cf_call{}) -> ok).
-spec(say/5 :: (Say :: binary(), Type :: binary(), Method :: binary(), Language :: binary(), Call :: #cf_call{}) -> ok).

say(Say, Call) ->
    say(Say, <<"name_spelled">>, Call).
say(Say, Type, Call) ->
    say(Say, Type, <<"pronounced">>, Call).
say(Say, Type, Method, Call) ->
    say(Say, Type, Method, <<"en">>, Call).
say(Say, Type, Method, Language, #cf_call{call_id=CallId, amqp_q=AmqpQ}=Call) ->
    Command = [
                {<<"Application-Name">>, <<"say">>}
               ,{<<"Say-Text">>, Say}
               ,{<<"Type">>, Type}
               ,{<<"Method">>, Method}
               ,{<<"Language">>, Language}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:say_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

say_command(Say, Type, Method, Language, #cf_call{call_id=CallId}) ->
    [
      {<<"Application-Name">>, <<"say">>}
     ,{<<"Say-Text">>, Say}
     ,{<<"Type">>, Type}
     ,{<<"Method">>, Method}
     ,{<<"Language">>, Language}
     ,{<<"Call-ID">>, CallId}
    ].

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to bridge a caller
%% with a conference, with optional entry flags
%% @end
%%--------------------------------------------------------------------
-spec(conference/2 :: (ConfId :: binary(), Call :: #cf_call{}) -> ok).
-spec(conference/3 :: (ConfId :: binary(), Mute :: binary(), Call :: #cf_call{}) -> ok).
-spec(conference/4 :: (ConfId :: binary(), Mute :: binary(), Deaf :: binary(), Call :: #cf_call{}) -> ok).
-spec(conference/5 :: (ConfId :: binary(), Mute :: binary(), Deaf :: binary(), Moderator :: binary(), Call :: #cf_call{}) -> ok).

-spec(b_conference/2 :: (ConfId :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_conference/3 :: (ConfId :: binary(), Mute :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_conference/4 :: (ConfId :: binary(), Mute :: binary(), Deaf :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(b_conference/5 :: (ConfId :: binary(), Mute :: binary(), Deaf :: binary(), Moderator :: binary(), Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).

conference(ConfId, Call) ->
    conference(ConfId, <<"false">>, Call).
conference(ConfId, Mute, Call) ->
    conference(ConfId, Mute, <<"false">>, Call).
conference(ConfId, Mute, Deaf, Call) ->
    conference(ConfId, Mute, Deaf, <<"false">>, Call).
conference(ConfId, Mute, Deaf, Moderator, #cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    Command = [
                {<<"Application-Name">>, <<"conference">>}
               ,{<<"Conference-ID">>, ConfId}
               ,{<<"Mute">>, Mute}
               ,{<<"Deaf">>, Deaf}
               ,{<<"Moderator">>, Moderator}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:conference_req([ KV || {_, V}=KV <- Command, V =/= undefined ]),
    send_callctrl(Payload, Call).

b_conference(ConfId, Call) ->
    b_conference(ConfId, <<"false">>, Call).
b_conference(ConfId, Mute, Call) ->
    b_conference(ConfId, Mute, <<"false">>, Call).
b_conference(ConfId, Mute, Deaf, Call) ->
    b_conference(ConfId, Mute, Deaf, <<"false">>, Call).
b_conference(ConfId, Mute, Deaf, Moderator, Call) ->
    conference(ConfId, Mute, Deaf, Moderator, Call),
    wait_for_message(<<"conference">>, <<"CHANNEL_EXECUTE">>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to preform a noop
%% @end
%%--------------------------------------------------------------------
-spec(noop/1 :: (Call :: #cf_call{}) -> ok).
-spec(b_noop/1 :: (Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).

noop(#cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    Command = [
                {<<"Application-Name">>, <<"noop">>}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:noop_req(Command),
    send_callctrl(Payload, Call).

b_noop(Call) ->
    noop(Call),
    wait_for_message(<<"noop">>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Produces the low level whistle_api request to flush the command
%% queue
%% @end
%%--------------------------------------------------------------------
-spec(flush/1 :: (Call :: #cf_call{}) -> tuple(ok, json_object()) | tuple(error, atom())).

flush(#cf_call{call_id=CallId, amqp_q=AmqpQ} = Call) ->
    Command = [
                {<<"Application-Name">>, <<"noop">>}
               ,{<<"Insert-At">>, <<"flush">>}
               ,{<<"Call-ID">>, CallId}
               | whistle_api:default_headers(AmqpQ, <<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)
              ],
    {ok, Payload} = whistle_api:noop_req(Command),
    send_callctrl(Payload, Call),
    wait_for_message(<<"noop">>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Low level function to consume call events, looping until a specific
%% one occurs.  If the channel is hungup or no call events are recieved
%% for the optional timeout period then errors are returned.
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_message/1 :: (Application :: binary()) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(wait_for_message/2 :: (Application :: binary(), Event :: binary()) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(wait_for_message/3 :: (Application :: binary(), Event :: binary(), Type :: binary()) -> tuple(ok, json_object()) | tuple(error, atom())).
-spec(wait_for_message/4 :: (Application :: binary(), Event :: binary(), Type :: binary(), Timeout :: integer() | false) -> tuple(ok, json_object()) | tuple(error, atom())).

wait_for_message(Application) ->
    wait_for_message(Application, <<"CHANNEL_EXECUTE_COMPLETE">>).
wait_for_message(Application, Event) ->
    wait_for_message(Application, Event, <<"call_event">>).
wait_for_message(Application, Event, Type) ->
    wait_for_message(Application, Event, Type, 5000).
wait_for_message(Application, Event, Type, false) ->
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Application-Name">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj), wh_json:get_value(<<"Event-Category">>, JObj) } of
                { _, <<"CHANNEL_HANGUP">>, <<"call_event">> } ->
                    {error, channel_hungup};
                { _, _, <<"error">> } ->
                    {error, execution_failure};
                { Application, Event, Type } ->
                    {ok, JObj};
		_ ->
		    wait_for_message(Application, Event, Type, false)
	    end
    end;
wait_for_message(Application, Event, Type, Timeout) ->
    Start = erlang:now(),
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Application-Name">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj), wh_json:get_value(<<"Event-Category">>, JObj) } of
                { _, <<"CHANNEL_HANGUP">>, <<"call_event">> } ->
                    {error, channel_hungup};
                { _, _, <<"error">> } ->
                    {error, execution_failure};
                { Application, Event, Type } ->
                    {ok, JObj};
		_ ->
		    DiffMicro = timer:now_diff(erlang:now(), Start),
                    wait_for_message(Application, Event, Type, Timeout - (DiffMicro div 1000))
            end
    after
        Timeout ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wait for a DTMF event and extract the digits when it comes
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_dtmf/1 :: (Timeout :: integer()) -> tuple(ok, binary()) | tuple(error, atom())).
wait_for_dtmf(Timeout) ->
    Start = erlang:now(),
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Event-Name">>, JObj), wh_json:get_value(<<"Event-Category">>, JObj) } of
                { <<"DTMF">>, <<"call_event">> } ->
                    {ok, wh_json:get_value(<<"DTMF-Digit">>, JObj)};
                { <<"CHANNEL_HANGUP">>, <<"call_event">> } ->
                    {error, channel_hungup};
                {  _, <<"error">> } ->
                    {error, execution_failure};
                _ ->
		    DiffMicro = timer:now_diff(erlang:now(), Start),
                    wait_for_dtmf(Timeout - (DiffMicro div 1000))
            end
    after
        Timeout ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Waits for and determines the status of the bridge command
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_bridge/1 :: (Timeout :: integer()) -> tuple(ok, json_object()) | tuple(error, atom())).
wait_for_bridge(Timeout) ->
    Start = erlang:now(),
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Application-Name">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj), wh_json:get_value(<<"Event-Category">>, JObj) } of
                { _, <<"CHANNEL_BRIDGE">>, <<"call_event">> } ->
                    {ok, JObj};
                { <<"bridge">>, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"call_event">> } ->
                    case wh_json:get_value(<<"Application-Response">>, JObj) of
                        <<"SUCCESS">> -> {ok, JObj};
                        Cause -> {error, {bridge_failed, Cause}}
                    end;
                { _, <<"CHANNEL_HANGUP">>, <<"call_event">> } ->
                    {error, channel_hungup};
                { _, _, <<"error">> } ->
                    {error, execution_failed};
                _ ->
		    DiffMicro = timer:now_diff(erlang:now(), Start),
                    wait_for_bridge(Timeout - (DiffMicro div 1000))
            end
    after
        Timeout ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Waits for and determines the status of the bridge command
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_application_or_dtmf/2 :: (Application :: binary(), Timeout :: integer()) -> tuple(ok, json_object()) | tuple(error, atom()) | tuple(dtmf, binary())).
wait_for_application_or_dtmf(Application, Timeout) ->
    Start = erlang:now(),
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Application-Name">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj), wh_json:get_value(<<"Event-Category">>, JObj) } of
                { Application, <<"CHANNEL_EXECUTE_COMPLETE">>, <<"call_event">> } ->
                    {ok, JObj};
                { _, <<"DTMF">>, <<"call_event">> } ->
                    {dtmf, wh_json:get_value(<<"DTMF-Digit">>, JObj)};
                { _, <<"CHANNEL_HANGUP">>, <<"call_event">> } ->
                    {error, channel_hungup};
                { _, _, <<"error">> } ->
                    {error, execution_failure};
                _ ->
		    DiffMicro = timer:now_diff(erlang:now(), Start),
                    wait_for_application_or_dtmf(Application, Timeout - (DiffMicro div 1000))
            end
    after
        Timeout ->
            {error, timeout}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wait forever for the channel to hangup
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_unbridge/0 :: () -> tuple(ok, channel_hungup | channel_unbridge) | tuple(error, execution_failure)).
wait_for_unbridge() ->
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Event-Category">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj) } of
                { <<"call_event">>, <<"CHANNEL_UNBRIDGE">> } ->
                    {ok, channel_unbridge};
                { <<"call_event">>, <<"CHANNEL_HANGUP">> } ->
                    {ok, channel_hungup};
                { <<"error">>, _ } ->
                    {error, execution_failure};
                _ ->
                    wait_for_unbridge()
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Wait forever for the channel to hangup
%% @end
%%--------------------------------------------------------------------
-spec(wait_for_hangup/0 :: () -> tuple(ok, channel_hungup) | tuple(error, execution_failure)).
wait_for_hangup() ->
    receive
        {amqp_msg, {struct, _}=JObj} ->
            case { wh_json:get_value(<<"Event-Category">>, JObj), wh_json:get_value(<<"Event-Name">>, JObj) } of
                { <<"call_event">>, <<"CHANNEL_HANGUP">> } ->
                    {ok, channel_hungup};
                { <<"error">>, _ } ->
                    {error, execution_failure};
                _ ->
                    wait_for_hangup()
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Sends call commands to the appropriate call control process
%% @end
%%--------------------------------------------------------------------
-spec(send_callctrl/2 :: (Payload :: binary(), Call :: #cf_call{}) -> ok).
send_callctrl(Payload, #cf_call{ctrl_q=CtrlQ}) ->
    amqp_util:callctl_publish(CtrlQ, Payload).

-spec(find_callerid/2 :: (Type :: binary(), Call :: #cf_call{}) -> tuple(binary(), binary())).
find_callerid(raw, _) ->
    {undefined, undefined};
find_callerid(Type, #cf_call{authorizing_id=RootId, account_db=Db}) ->
    case couch_mgr:get_all_results(Db, <<"callerid/find_caller_id">>) of 
        {ok, JObj} ->
            CIDs = [
                    {wh_json:get_value(<<"key">>, C), wh_json:get_value(<<"value">>, C)}
                    || C <- JObj
                  ],
            CID = search_for_callerid(RootId, Type, CIDs),
            {wh_json:get_value(<<"number">>, CID, <<>>), wh_json:get_value(<<"name">>, CID, <<>>)};
        {error, _} ->
            {<<>>, <<>>}
    end.

-spec(search_for_callerid/3 :: (NodeId :: binary(), Type :: binary(), CIDs :: proplist()) -> undefined | json_object()).
search_for_callerid(NodeId, Type, CIDs) ->
    logger:format_log(info, "Looking on ~p for ~p", [NodeId, Type]),
    Node = props:get_value(NodeId, CIDs),
    case wh_json:get_value([<<"callerid">>, Type], Node) of
        undefined when NodeId =/= <<"account">> ->
            search_for_callerid(wh_json:get_value(<<"next">>, Node, <<"account">>), Type, CIDs);
        undefined ->
            wh_json:get_value([<<"callerid">>, <<"default">>], Node);
        CID ->
            CID
    end.
