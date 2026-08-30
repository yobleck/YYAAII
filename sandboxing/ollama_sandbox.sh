#!/bin/sh
# this script sets up the isolated network namespace
# for ollama to run in, so it can't connect to the internet
# should be an isolated loopback only
ip netns add ollama_net_sandbox
sleep 0.05
ip netns exec ollama_net_sandbox ip link set lo up  # unshare(1) brings down for some reason
echo "ollama sandbox test" >> ~/test.txt