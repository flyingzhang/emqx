# Kick Behavior Issue Documentation

This directory contains documentation, analysis, and verification scripts related to the `--retain-session` kick behavior fix.

## Problem Description

The `emqx ctl clients kick --retain-session` command was not working as expected. Sessions were destroyed even when the flag was provided.

## Root Cause

1. **Missing Handler**: `emqx_channel` lacked a `handle_info({kick, Opts}, ...)` clause.
2. **Session Type**: Memory-based sessions cannot survive process termination.
3. **Session Resurrection**: `terminate/2` was saving session state, resurrecting destroyed sessions.

## Solution

See [SOLUTION.md](./SOLUTION.md) for details.

## Files

- `SOLUTION.md` - Detailed technical solution
- `verify_kick_fix_full.py` - Verification script for Kick/Retain logic
- `test_repeated_kick.py` - Verification script for Repeated Kick regression
- `emqx.conf.example` - Example configuration with Durable Sessions

## Verification

```bash
# Start EMQX with Durable Sessions enabled
docker run -d --name emqx-verify -p 1883:1883 \
  -e EMQX_DURABLE_SESSIONS__ENABLE=true \
  -e EMQX_DURABLE_STORAGE__MESSAGES__BACKEND=builtin_local \
  -e EMQX_CLUSTER__DISCOVERY_STRATEGY=singleton \
  emqx/emqx:5.8.8

# Run verification (Primary Fix)
python verify_kick_fix_full.py

# Run verification (Repeated Kick Regression)
python test_repeated_kick.py
```
