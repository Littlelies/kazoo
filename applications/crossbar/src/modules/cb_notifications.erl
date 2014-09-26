%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2014, 2600Hz INC
%%% @doc
%%%
%%% Listing of all expected v1 callbacks
%%%
%%% @end
%%% @contributors:
%%%   Karl Anderson
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(cb_notifications).

-export([init/0
         ,allowed_methods/0, allowed_methods/1, allowed_methods/2
         ,resource_exists/0, resource_exists/1, resource_exists/2
         ,content_types_provided/3
         ,content_types_accepted/3
         ,validate/1, validate/2, validate/3
         ,put/1
         ,post/2, post/3
         ,delete/2
        ]).

-include("../crossbar.hrl").


-define(NOTIFICATION_MIME_TYPES, [{<<"text">>, <<"html">>}
                                  ,{<<"text">>, <<"plain">>}
                                 ]).
-define(HTML, <<"html">>).
-define(TXT, <<"text">>).
-define(CB_LIST, <<"notifications/crossbar_listing">>).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Initializes the bindings this module will respond to.
%% @end
%%--------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.allowed_methods.notifications">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.notifications">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.content_types_provided.notifications">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.content_types_accepted.notifications">>, ?MODULE, 'content_types_accepted'),
    _ = crossbar_bindings:bind(<<"*.validate.notifications">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.notifications">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.notifications">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.notifications">>, ?MODULE, 'delete').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%--------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
-spec allowed_methods(path_token()) -> http_methods().
-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].
allowed_methods(_) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE].
allowed_methods(_, ?HTML) ->
    [?HTTP_GET, ?HTTP_POST];
allowed_methods(_, ?TXT) ->
    [?HTTP_GET, ?HTTP_POST].

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Does the path point to a valid resource
%% So /notifications => []
%%    /notifications/foo => [<<"foo">>]
%%    /notifications/foo/bar => [<<"foo">>, <<"bar">>]
%% @end
%%--------------------------------------------------------------------
-spec resource_exists() -> 'true'.
-spec resource_exists(path_token()) -> 'true'.
resource_exists() -> 'true'.
resource_exists(_) -> 'true'.
resource_exists(_, ?HTML) -> 'true';
resource_exists(_, ?TXT) -> 'true'.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Add content types accepted and provided by this module
%%
%% @end
%%--------------------------------------------------------------------
-spec content_types_provided(cb_context:context(), path_token(), path_token()) ->
                                    cb_context:context().
-spec content_types_provided(cb_context:context(), path_token(), path_token(), http_method()) ->
                                    cb_context:context().
content_types_provided(Context, Id, Format) ->
    content_types_provided(Context, fix_id(Id), Format, cb_context:req_verb(Context)).

content_types_provided(Context, Id, _Format, ?HTTP_GET) ->
    Context1 = read(Id, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            JObj = cb_context:doc(Context1),
            case wh_json:get_keys(wh_json:get_value([<<"_attachments">>], JObj, [])) of
                [] -> Context;
                [Attachment|_] ->
                    CT = wh_json:get_value([<<"_attachments">>, Attachment, <<"content_type">>], JObj),
                    [Type, SubType] = binary:split(CT, <<"/">>),
                    cb_context:set_content_types_provided(Context, [{'to_binary', [{Type, SubType}]}])
            end;
        _Status -> Context1
    end;
content_types_provided(Context, _Id, _, _Verb) ->
    Context.

-spec content_types_accepted(cb_context:context(), path_token(), path_token()) ->
                                    cb_context:context().
-spec content_types_accepted_for_upload(cb_context:context(), http_method()) ->
                                               cb_context:context().
content_types_accepted(Context, _Id, _Format) ->
    content_types_accepted_for_upload(Context, cb_context:req_verb(Context)).

content_types_accepted_for_upload(Context, ?HTTP_POST) ->
    CTA = [{'from_binary', ?NOTIFICATION_MIME_TYPES}],
    cb_context:set_content_types_accepted(Context, CTA);
content_types_accepted_for_upload(Context, _Verb) ->
    Context.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /notifications mights load a list of skel objects
%% /notifications/123 might load the skel object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%--------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
-spec validate(cb_context:context(), path_token()) -> cb_context:context().
-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context) ->
    case is_authorized(Context) of
        'true' ->
            validate_notifications(Context, cb_context:req_verb(Context));
        'false' ->
            cb_context:add_system_error('forbidden', Context)
    end.

validate(Context, Id) ->
    case is_authorized(Context) of
        'true' ->
            validate_notifications(Context, fix_id(Id), cb_context:req_verb(Context));
        'false' ->
            cb_context:add_system_error('forbidden', Context)
    end.

validate(Context, Id, ?HTML) ->
    case is_authorized(Context) of
        'true' ->
            lager:debug("uploading hml template to '~s'", [Id]),
            validate_template(Context, fix_id(Id), cb_context:req_verb(Context), cb_context:req_files(Context));
    'false' ->
            cb_context:add_system_error('forbidden', Context)
    end;
validate(Context, Id, ?TXT) ->
    case is_authorized(Context) of
        'true' ->
            lager:debug("uploading txt template data to '~s'", [Id]),
            validate_template(Context, fix_id(Id), cb_context:req_verb(Context), cb_context:req_files(Context));
    'false' ->
            cb_context:add_system_error('forbidden', Context)
    end.

-spec is_authorized(cb_context:context()) -> boolean().
-spec is_authorized(cb_context:context(), ne_binary(), wh_proplist()) -> boolean().
is_authorized(Context) ->
    is_authorized(Context, cb_context:auth_account_id(Context), cb_context:req_nouns(Context)).

is_authorized(_, AuthAccountId, [{<<"notifications">>, _}, {<<"accounts">>, AccountId}|_]) ->
    wh_services:is_reseller(AuthAccountId) andalso
        wh_util:is_in_account_hierarchy(AuthAccountId, AccountId, 'true');
is_authorized(_, AuthAccountId, [{<<"notifications">>, _}|_]) ->
    AuthAccountId =:= whapps_util:get_master_account_id().

-spec validate_notifications(cb_context:context(), http_method()) -> cb_context:context().
validate_notifications(Context, ?HTTP_GET) ->
    summary(Context);
validate_notifications(Context, ?HTTP_PUT) ->
    create(Context).

-spec validate_notifications(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_notifications(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_notifications(Context, Id, ?HTTP_POST) ->
    update(Id, Context);
validate_notifications(Context, Id, ?HTTP_DELETE) ->
    read(Id, Context).

-spec validate_template(cb_context:context(), ne_binary(), http_method(), wh_proplist()) -> cb_context:context().
validate_template(Context, Id, ?HTTP_GET, _Files) ->
    lager:debug("fetch template contents for '~s'", [Id]),
    load_template(Id, Context);
validate_template(Context, _Id, ?HTTP_POST, []) ->
    Message = <<"please provide an template file">>,
    cb_context:add_validation_error(<<"file">>, <<"required">>, Message, Context);
validate_template(Context, Id, ?HTTP_POST, [{_Filename, File}]) ->
    case test_compile_template(File) of
        'error' ->
            crossbar_util:response('error', <<"Invalid template">>, 400, Context);
        'ok' ->
            Context1 = read(Id, Context),
            case cb_context:resp_status(Context1) of
                'success' ->
                    lager:debug("loaded media meta for '~s'", [Id]),
                    Context1;
                _Status -> Context1
            end
    end.

-spec test_compile_template(wh_json:object()) -> 'ok' | 'error'.
test_compile_template(File) ->
    Template = wh_json:get_value(<<"contents">>, File),
    % Atom leak !!!!
    {_, _, Now} = erlang:now(),
    Name = wh_util:to_atom(Now, 'true'),
    case erlydtl:compile_template(Template, Name, [{'out_dir', 'false'}]) of
        {'ok', CustomTemplate} ->
            lager:debug("template compiled successfuly, purging now"),
            code:purge(CustomTemplate),
            code:delete(CustomTemplate),
            'ok';
        {'error', _R} ->
            lager:error("fail to compile template: ~p", [_R]),
            'error';
        _E ->
            lager:error("fail to compile template"),
            'error'
    end.


%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%--------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%--------------------------------------------------------------------
-spec post(cb_context:context(), path_token()) -> cb_context:context().
-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, _) ->
    crossbar_doc:save(Context).

post(Context, Id, Format) ->
    update_template(Context, fix_id(Id), Format, cb_context:req_files(Context)).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%--------------------------------------------------------------------
-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    crossbar_doc:delete(Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Create a new instance with the data provided, if it is valid
%% @end
%%--------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    cb_context:validate_request_data(<<"notifications">>, Context, OnSuccess).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load an instance from the database
%% @end
%%--------------------------------------------------------------------
-spec read(ne_binary(), cb_context:context()) -> cb_context:context().
read(<<"notify_", ShortId/binary>>=Id, Context) ->
    Context1 = crossbar_doc:load(Id, Context),
    RespData = cb_context:resp_data(Context1),
    cb_context:set_resp_data(Context1, wh_json:set_value(<<"id">>, ShortId, RespData)).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%--------------------------------------------------------------------
-spec update(ne_binary(), cb_context:context()) -> cb_context:context().
update(Id, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(Id, C) end,
    cb_context:validate_request_data(<<"notifications">>, Context, OnSuccess).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%--------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    crossbar_doc:load_view(?CB_LIST, [], Context, fun normalize_view_results/2).

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec on_successful_validation(api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', Context) ->
    Doc = cb_context:doc(Context),
    Id = fix_id(wh_json:get_value(<<"id">>, Doc)),
    Doc1 = wh_json:set_values([{<<"pvt_type">>, <<"notification">>}
                               ,{<<"_id">>, Id}
                             ], Doc),
    Doc2 = wh_json:delete_key(<<"id">>, Doc1),
    cb_context:set_doc(Context, Doc2);
on_successful_validation(Id, Context) ->
    crossbar_doc:load_merge(Id, Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Normalizes the resuts of a view
%% @end
%%--------------------------------------------------------------------
-spec normalize_view_results(wh_json:object(), wh_json:objects()) -> wh_json:objects().
normalize_view_results(JObj, Acc) ->
    [wh_json:get_value(<<"value">>, JObj)|Acc].

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec fix_id(ne_binary()) -> ne_binary().
fix_id(<<"notify_", _/binary>>=Id) -> Id;
fix_id(Id) -> <<"notify_", Id/binary>>.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load the binary attachment of a media doc
%% @end
%%--------------------------------------------------------------------
-spec load_template(cb_context:context(), path_token()) -> cb_context:context().
load_template(Id, Context) ->
    Context1 = read(Id, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            Meta = wh_json:get_value([<<"_attachments">>], cb_context:doc(Context1), []),
            case wh_json:get_keys(Meta) of
                [] -> crossbar_util:response_bad_identifier(Id, Context);
                [Attachment|_] ->
                    cb_context:add_resp_headers(
                      crossbar_doc:load_attachment(cb_context:doc(Context1), Attachment, Context1)
                      ,[{<<"Content-Disposition">>, <<"attachment; filename=", Attachment/binary>>}
                        ,{<<"Content-Type">>, wh_json:get_value([Attachment, <<"content_type">>], Meta)}
                        ,{<<"Content-Length">>, wh_json:get_value([Attachment, <<"length">>], Meta)}
                       ])
            end;
        _Status -> Context1
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Update the binary attachment of a media doc
%% @end
%%--------------------------------------------------------------------
-spec update_template(cb_context:context(), path_token(), path_token(), req_files()) ->
                                 cb_context:context().
update_template(Context, Id, Format, [{_, FileObj}|_]) ->
    Contents = wh_json:get_value(<<"contents">>, FileObj),
    CT = wh_json:get_value([<<"headers">>, <<"content_type">>], FileObj),
    lager:debug("file content type: ~s", [CT]),
    Opts = [{'headers', [{'content_type', wh_util:to_list(CT)}]}],
    crossbar_doc:save_attachment(
        Id
        ,<<"template.", Format/binary>>
        ,Contents
        ,Context
        ,Opts
    ).