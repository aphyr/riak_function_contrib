-module(bucket_reloader).
%% -------------------------------------------------------------------
%%
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%  http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-export([reload/4,
        reload/5]).

reload(FromServer, ToServer, Bucket, NewBucket) ->
 reload(FromServer, ToServer, Bucket, NewBucket, 1.0).

reload(FromServer, ToServer, Bucket, NewBucket, InputSize) ->
   {ok, CFrom} = riak:client_connect(FromServer),
   {ok, CTo} = riak:client_connect(ToServer),
   {ok, Keys0} = CFrom:list_keys(Bucket),
   Keys = truncate_keys(Keys0, InputSize),
   io:format("Transferring ~p keys~n", [length(Keys)]),
   transfer(CFrom, CTo, Bucket, NewBucket, Keys, 0).

transfer(_CFrom, _CTo, _Bucket, _NewBucket, [], _) ->
   io:format("~n"),
   ok;
transfer(CFrom, CTo, Bucket, NewBucket, [H|T], Count) when is_binary(H) ->
   Owner = self(),
   proc_lib:spawn(fun() ->
                          case CFrom:get(Bucket, H) of
                              {ok, FromObj} ->
                                  OldObj = riak_object:get_value(FromObj),
                                  OldKey = riak_object:key(FromObj),
                                  OldContentType = riak_object:key(FromObj),
                                  Object = riak_object:new(NewBucket, OldKey, OldObj, OldContentType),
                                  CTo:put(Object, 1),
                                  io:format("."),
                                  Owner ! done;
                              Error ->
                                  error_logger:error_msg("Error fetching ~p/~p: ~p~n", [Bucket, H, Error]),
                                  Owner ! done
                          end end),
   NewCount = if
                  Count == 250 ->
                      let_workers_catch_up(Count),
                      0;
                  true ->
                      Count + 1
              end,
   transfer(CFrom, CTo, Bucket, NewBucket, T, NewCount).

let_workers_catch_up(0) ->
   ok;
let_workers_catch_up(Count) ->
   receive
       done ->
           ok
   end,
   let_workers_catch_up(Count - 1).

truncate_keys(Keys, 1.0) ->
   Keys;
truncate_keys(Keys, InputSize) ->
   TargetSize = erlang:round(length(Keys) * InputSize),
   {Keys1, _} = lists:split(TargetSize, Keys),
   Keys1.