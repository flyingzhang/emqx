#!/usr/bin/env python3
"""
Reproduce the repeated kick bug:
After a client is kicked once, it should be able to reconnect normally.
This script verifies that the kick state is NOT persisted.
"""
import paho.mqtt.client as mqtt
import subprocess
import time
import sys

BROKER_HOST = "localhost"
BROKER_PORT = 1883
CLIENT_ID = f"repeated-kick-test-{int(time.time())}"

def on_connect(client, userdata, flags, rc, *args):
    print(f"  Connected! RC: {rc}")
    userdata['connected'] = True
    userdata['session_present'] = getattr(flags, 'session_present', False) if hasattr(flags, 'session_present') else bool(flags)

def on_disconnect(client, userdata, rc, *args):
    print(f"  Disconnected! RC: {rc}")
    userdata['disconnected'] = True

def create_client():
    userdata = {'connected': False, 'disconnected': False, 'session_present': None}
    client = mqtt.Client(
        client_id=CLIENT_ID,
        protocol=mqtt.MQTTv5,
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2
    )
    client.user_data_set(userdata)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    return client, userdata

def kick_client(retain_session=False):
    cmd = f"docker exec emqx-verify emqx ctl clients kick {CLIENT_ID}"
    if retain_session:
        cmd += " --retain-session"
    print(f"  Executing: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print(f"  Result: {result.stdout.strip()}")
    return result.returncode == 0

def test_repeated_kick():
    print(f"\n=== Testing Repeated Kick Bug (ClientID: {CLIENT_ID}) ===\n")
    
    # Step 1: Connect
    print("[Step 1] First connection...")
    client, userdata = create_client()
    client.connect(BROKER_HOST, BROKER_PORT, clean_start=False, properties=mqtt.Properties(mqtt.PacketTypes.CONNECT))
    client.loop_start()
    time.sleep(2)
    
    if not userdata['connected']:
        print("  FAIL: Could not connect initially")
        return False
    
    # Step 2: Kick the client
    print("\n[Step 2] Kicking client...")
    time.sleep(1)
    kick_client(retain_session=False)
    time.sleep(2)
    
    if not userdata['disconnected']:
        print("  WARN: Client did not detect disconnect")
    
    client.loop_stop()
    client.disconnect()
    
    # Step 3: Reconnect - this should succeed without getting kicked again
    print("\n[Step 3] Reconnecting (should NOT be kicked again)...")
    client2, userdata2 = create_client()
    client2.connect(BROKER_HOST, BROKER_PORT, clean_start=False, properties=mqtt.Properties(mqtt.PacketTypes.CONNECT))
    client2.loop_start()
    
    # Wait a bit to see if we get kicked
    time.sleep(5)
    
    if userdata2['disconnected']:
        print("\n  *** BUG CONFIRMED: Client was kicked again on reconnect! ***")
        client2.loop_stop()
        return False
    
    if userdata2['connected']:
        print("\n  SUCCESS: Client reconnected and stayed connected!")
        client2.loop_stop()
        client2.disconnect()
        return True
    
    print("\n  FAIL: Unexpected state")
    client2.loop_stop()
    return False

if __name__ == "__main__":
    success = test_repeated_kick()
    sys.exit(0 if success else 1)
