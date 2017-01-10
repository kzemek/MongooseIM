%%%----------------------------------------------------------------------
%%% File    : mod_adhoc.erl
%%% Author  : Magnus Henoch <henoch@dtek.chalmers.se>
%%% Purpose : Handle incoming ad-doc requests (XEP-0050)
%%% Created : 15 Nov 2005 by Magnus Henoch <henoch@dtek.chalmers.se>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2011   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------
-module(mod_adhoc).
-author('henoch@dtek.chalmers.se').

-behaviour(gen_mod).

-export([start/2,
         stop/1,
         process_local_iq/3,
         process_sm_iq/3,
         get_local_commands/5,
         get_local_identity/5,
         get_local_features/5,
         get_sm_commands/5,
         get_sm_identity/5,
         get_sm_features/5,
         ping_item/4,
         ping_command/4]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("adhoc.hrl").

start(Host, Opts) ->
    IQDisc = gen_mod:get_opt(iqdisc, Opts, one_queue),

    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_COMMANDS,
                                  ?MODULE, process_local_iq, IQDisc),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_COMMANDS,
                                  ?MODULE, process_sm_iq, IQDisc),

    ejabberd_hooks:add(disco_local_identity, Host, ?MODULE, get_local_identity, 99),
    ejabberd_hooks:add(disco_local_features, Host, ?MODULE, get_local_features, 99),
    ejabberd_hooks:add(disco_local_items, Host, ?MODULE, get_local_commands, 99),
    ejabberd_hooks:add(disco_sm_identity, Host, ?MODULE, get_sm_identity, 99),
    ejabberd_hooks:add(disco_sm_features, Host, ?MODULE, get_sm_features, 99),
    ejabberd_hooks:add(disco_sm_items, Host, ?MODULE, get_sm_commands, 99),
    ejabberd_hooks:add(adhoc_local_items, Host, ?MODULE, ping_item, 100),
    ejabberd_hooks:add(adhoc_local_commands, Host, ?MODULE, ping_command, 100).

stop(Host) ->
    ejabberd_hooks:delete(adhoc_local_commands, Host, ?MODULE, ping_command, 100),
    ejabberd_hooks:delete(adhoc_local_items, Host, ?MODULE, ping_item, 100),
    ejabberd_hooks:delete(disco_sm_items, Host, ?MODULE, get_sm_commands, 99),
    ejabberd_hooks:delete(disco_sm_features, Host, ?MODULE, get_sm_features, 99),
    ejabberd_hooks:delete(disco_sm_identity, Host, ?MODULE, get_sm_identity, 99),
    ejabberd_hooks:delete(disco_local_items, Host, ?MODULE, get_local_commands, 99),
    ejabberd_hooks:delete(disco_local_features, Host, ?MODULE, get_local_features, 99),
    ejabberd_hooks:delete(disco_local_identity, Host, ?MODULE, get_local_identity, 99),

    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_COMMANDS),
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_COMMANDS).

%%-------------------------------------------------------------------------

-spec get_local_commands(Acc :: mongoose_stanza:t(),
                         From :: ejabberd:jid(),
                         To :: ejabberd:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> mongoose_stanza:t().
get_local_commands(Acc, _From, #jid{lserver = LServer} = _To, <<"">>, Lang) ->
    Display = gen_mod:get_module_opt(LServer, ?MODULE, report_commands_node, false),
    case Display of
        false ->
            Acc;
        _ ->
            Nodes = [#xmlel{name = <<"item">>,
                            attrs = [{<<"jid">>, LServer},
                                     {<<"node">>, ?NS_COMMANDS},
                                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]}],
            mongoose_stanza:append(local_items, Nodes, Acc)
    end;
get_local_commands(Acc, From, #jid{lserver = LServer} = To, ?NS_COMMANDS, Lang) ->
    ejabberd_hooks:run_fold(adhoc_local_items, LServer, Acc, [From, To, Lang]);
get_local_commands(Acc, _From, _To, <<"ping">>, _Lang) ->
    Acc;
get_local_commands(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_sm_commands(Acc :: mongoose_stanza:t(),
                      From :: ejabberd:jid(),
                      To :: ejabberd:jid(),
                      NS :: binary(),
                      ejabberd:lang()) -> mongoose_stanza:t().
get_sm_commands(Acc, _From, #jid{lserver = LServer} = To, <<"">>, Lang) ->
    Display = gen_mod:get_module_opt(LServer, ?MODULE, report_commands_node, false),
    case Display of
        false ->
            Acc;
        _ ->
            Nodes = [#xmlel{name = <<"item">>,
                            attrs = [{<<"jid">>, jid:to_binary(To)},
                                     {<<"node">>, ?NS_COMMANDS},
                                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]}],
            mongoose_stanza:append(sm_items, Nodes, Acc)
    end;

get_sm_commands(Acc, From, #jid{lserver = LServer} = To, ?NS_COMMANDS, Lang) ->
    ejabberd_hooks:run_fold(adhoc_sm_items, LServer, Acc, [From, To, Lang]);

get_sm_commands(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

%% @doc On disco info request to the ad-hoc node, return automation/command-list.
-spec get_local_identity(Acc :: mongoose_stanza:t(),
                         From :: ejabberd:jid(),
                         To :: ejabberd:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> mongoose_stanza:t().
get_local_identity(Acc, From, To, Ns, Lang) ->
    LId = do_get_local_identity(From, To, Ns, Lang),
    mongoose_stanza:append(local_identity, LId, Acc).

do_get_local_identity(_From, _To, ?NS_COMMANDS, Lang) ->
    [#xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-list">>},
                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]}];
do_get_local_identity(_From, _To, <<"ping">>, Lang) ->
    [#xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-node">>},
                     {<<"name">>, translate:translate(Lang, <<"Ping">>)}]}];
do_get_local_identity(_From, _To, _Node, _Lang) ->
    [].

%%-------------------------------------------------------------------------

%% @doc On disco info request to the ad-hoc node, return automation/command-list.
-spec get_sm_identity(Acc :: mongoose_stanza:t(),
                     From :: ejabberd:jid(),
                     To :: ejabberd:jid(),
                     NS :: binary(),
                     ejabberd:lang()) -> mongoose_stanza:t().
get_sm_identity(Acc, _From, _To, ?NS_COMMANDS, Lang) ->
    Id = #xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-list">>},
                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]},
    maps:append(sm_identity, Id, Acc);
get_sm_identity(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_local_features(Acc :: mongoose_stanza:t(),
                         From :: ejabberd:jid(),
                         To :: ejabberd:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> mongoose_stanza:t().
get_local_features(Acc, _From, _To, <<"">>, _Lang) ->
    mongoose_stanza:append(features, ?NS_COMMANDS, Acc);
get_local_features(Acc, _From, _To, ?NS_COMMANDS, _Lang) ->
    %% override all lesser features...
    mongoose_stanza:put(features, [], Acc);
get_local_features(Acc, _From, _To, <<"ping">>, _Lang) ->
    %% override all lesser features...
    mongoose_stanza:put(features, [?NS_COMMANDS], Acc);
get_local_features(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_sm_features(Acc :: mongoose_stanza:t(),
                             From :: ejabberd:jid(),
                             To :: ejabberd:jid(),
                             NS :: binary(),
                             ejabberd:lang()) -> mongoose_stanza:t().
get_sm_features(Acc, _From, _To, <<"">>, _Lang) ->
    Feats = mongoose_stanza:get(sm_features, Acc, []),
    mongoose_stanza:put(sm_features, Feats ++ [?NS_COMMANDS], Acc);
get_sm_features(Acc, _From, _To, ?NS_COMMANDS, _Lang) ->
    %% override all lesser features...
    mongoose_stanza:put(sm_features, [], Acc);
get_sm_features(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec process_local_iq(ejabberd:jid(), ejabberd:jid(), ejabberd:iq()) ->
                                                        ignore | ejabberd:iq().
process_local_iq(From, To, IQ) ->
    process_adhoc_request(From, To, IQ, adhoc_local_commands).


-spec process_sm_iq(ejabberd:jid(), ejabberd:jid(), ejabberd:iq()) ->
                                                        ignore | ejabberd:iq().
process_sm_iq(From, To, IQ) ->
    process_adhoc_request(From, To, IQ, adhoc_sm_commands).


-spec process_adhoc_request(ejabberd:jid(), ejabberd:jid(), ejabberd:iq(),
        Hook :: atom()) -> ignore | ejabberd:iq().
process_adhoc_request(From, To, #iq{sub_el = SubEl} = IQ, Hook) ->
    ?DEBUG("About to parse ~p...", [IQ]),
    case adhoc:parse_request(IQ) of
        {error, Error} ->
            IQ#iq{type = error, sub_el = [SubEl, Error]};
        #adhoc_request{} = AdhocRequest ->
            Host = To#jid.lserver,
            Stanza = mongoose_stanza:new(),
            Resp = ejabberd_hooks:run_fold(Hook, Host, Stanza,
                                         [From, To, AdhocRequest]),
            case mongoose_stanza:get(response, Resp, ignore) of
                ignore ->
                    ignore;
                empty ->
                    IQ#iq{type = error, sub_el = [SubEl, ?ERR_ITEM_NOT_FOUND]};
                {error, Error} ->
                    IQ#iq{type = error, sub_el = [SubEl, Error]};
                Command ->
                    IQ#iq{type = result, sub_el = [Command]}
            end
    end.


-spec ping_item(Acc :: mongoose_stanza:t(),
                From :: ejabberd:jid(),
                To :: ejabberd:jid(),
                ejabberd:lang()) -> mongoose_stanza:t().
ping_item(Acc, _From, #jid{lserver = Server} = _To, Lang) ->
    Nodes = [#xmlel{name = <<"item">>,
                    attrs = [{<<"jid">>, Server},
                             {<<"node">>, <<"ping">>},
                             {<<"name">>, translate:translate(Lang, <<"Ping">>)}]}],
    mongoose_stanza:append({local_items, Nodes, Acc}).


-spec ping_command(Acc :: mongoose_stanza:t(),
                   From :: ejabberd:jid(),
                   To :: ejabberd:jid(),
                   adhoc:request()) -> mongoose_stanza:t().
ping_command(Acc, _From, _To,
             #adhoc_request{lang = Lang,
                            node = <<"ping">>,
                            session_id = _Sessionid,
                            action = Action} = Request) ->
    Response = if
        Action == <<"">>; Action == <<"execute">> ->
            adhoc:produce_response(
              Request,
              #adhoc_response{status = completed,
                              notes = [{<<"info">>, translate:translate(Lang, <<"Pong">>)}]});
        true ->
            {error, ?ERR_BAD_REQUEST}
    end,
    mongoose_stanza:put(response, Response, Acc);
ping_command(Acc, _From, _To, _Request) ->
    Acc.

