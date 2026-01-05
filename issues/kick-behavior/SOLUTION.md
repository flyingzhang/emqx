# Kick Retain-Session Fix - Technical Solution

## Problem

The `emqx ctl clients kick <ClientId> --retain-session` command was not preserving sessions.

### Root Causes

1.  **Missing `handle_info` clause**: `emqx_cm:kick_session` sends `{kick, Opts}` as a message. `emqx_channel` only had `handle_call({kick}, ...)`, not `handle_info({kick, Opts}, ...)`.

2.  **Memory Sessions Cannot Persist**: Default CE configuration uses `emqx_session_mem`. When the channel process terminates (kick), the session data is lost.

3.  **Session Resurrection Bug**: With Durable Sessions enabled, `emqx_channel:terminate` would call `emqx_session:terminate`, committing (saving) the in-memory session state back to the database. This resurrected sessions that `emqx_session:destroy` had just deleted.

## Solution

### Code Changes in `apps/emqx/src/emqx_channel.erl`

#### 1. Add `handle_info` clause for `{kick, Opts}`
```erlang
handle_info({kick, Opts}, Channel) ->
    ?EXT_TRACE_BROKER_DISCONNECT(
        ?EXT_TRACE_ATTR(
            maps:merge(basic_attrs(Channel), disconnect_attrs(kick, Channel))
        ),
        fun() ->
            case process_kick(Opts, Channel) of
                {shutdown, Reason, _Reply, NChannel} ->
                    {shutdown, Reason, NChannel};
                {shutdown, Reason, _Reply, _Packet, NChannel} ->
                    {shutdown, Reason, NChannel}
            end
        end,
        []
    );
```

#### 2. Use distinct shutdown reason in `process_kick`
```erlang
Reason =
    case maps:get(retain_session, Opts, false) of
        true -> kicked;
        false -> {kicked, destroy}
    end,
```

#### 3. Intercept `{kicked, destroy}` in `terminate/2`
```erlang
terminate({shutdown, {kicked, destroy}}, _Channel) ->
    ok;
```

### Configuration Requirements

Durable Sessions must be enabled for session retention to work:

```hocon
durable_sessions {
  enable = true
}
durable_storage {
  messages {
    backend = builtin_local
  }
}
cluster {
  discovery_strategy = singleton  # Required for builtin_local
}
```


## Regression: Repeated Kick Issue

A regression was identified where a kicked client (without retain-session) would be immediately kicked again upon reconnection.

### Root Cause
The initial fix in `emqx_channel:terminate` for `{shutdown, {kicked, destroy}}` simply returned `ok`, skipping **all** termination logic.
While `emqx_cm` relies on monitor DOWN events to clean up channels (which worked), other necessary cleanup side-effects (e.g., hooks) were skipped. This led to state inconsistencies, causing the new connection to be misidentified or interfere with the old one during `takeover`.

### Revised Solution

We must **skip session persistence (commit)** but **run all other termination hooks**.

1.  **Export `run_terminate_hooks/3`** from `emqx_session.erl`.
2.  **Update `emqx_channel:terminate/2`**:
    For `{shutdown, {kicked, destroy}}`, call `emqx_session:run_terminate_hooks` instead of `emqx_session:terminate`.

```erlang
terminate({shutdown, {kicked, destroy}}, Channel) ->
    %% Session was explicitly destroyed in process_kick; run hooks but skip session:terminate
    %% to prevent session resurrection via commit
    run_terminate_hook_only(kicked, Channel);

%% ...

run_terminate_hook_only(Reason, #channel{clientinfo = ClientInfo, session = Session}) ->
    emqx_session:run_terminate_hooks(ClientInfo, Reason, Session).
```

## Verification

Run `verify_kick_fix_full.py`:

| Case | Command | Expected | Actual |
|------|---------|----------|--------|
| Default Kick | `clients kick <ID>` | Session Destroyed | ✅ Pass |
| Retain Kick | `clients kick <ID> --retain-session` | Session Retained | ✅ Pass |

Run `test_repeated_kick.py`:
| Case | Steps | Expected | Actual |
|------|-------|----------|--------|
| Repeated Kick | Connect -> Kick -> Reconnect | Connection stable (not kicked again) | ✅ Pass |
