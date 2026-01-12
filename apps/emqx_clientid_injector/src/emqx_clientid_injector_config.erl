%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_clientid_injector_config).

%% API
-export([get_config/0, default_config/0]).

%% @doc 获取当前配置
get_config() ->
    case application:get_env(emqx_clientid_injector, config) of
        {ok, Config} -> Config;
        undefined -> default_config()
    end.

%% @doc 默认配置
default_config() ->
    #{
        enable => true,
        clientid_key => <<"x-emqx-clientid">>,
        inject_username => false,
        username_key => <<"x-emqx-username">>,
        inject_peername => false,
        peername_key => <<"x-emqx-peername">>,
        exclude_prefixes => [<<"$SYS/">>, <<"$share/">>],
        include_prefixes => []
    }.
