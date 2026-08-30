# isolate ollama from the internet and any folders it doesn't need access to
# fuck this fucking piece of shit program. firejail/bubblewrap/unshare/nsenter suck fucking donkey dick

name ollama_server_sandbox

noblacklist ${HOME}/.ollama/

#blacklist /
#blacklist /etc/
#blacklist ${HOME}
#blacklist /usr/

whitelist ${HOME}/.ollama/


caps.drop all
# below blocks unix sockets to cut off dbus
protocol inet
netns ollama_net_sandbox
#net none
#netfilter
#no3d
##nodbus (deprecated, use 'dbus-user none' and 'dbus-system none', see below)
nodvd
nogroups
noinput
nonewprivs
noprinters
noroot
nosound
notv
nou2f
novideo

# TODO private, private-home and private-lib all cause problems that need to be fixed to hide files from ollama
#private
private-cache
private-cwd
private-dev
private-tmp

#private-bin env
#private-bin echo
#private-bin ollama
#private-lib /usr/lib/ollama/llama-server
#private-bin stat
#private-bin pgrep
#private-bin pkill
#private-bin nnn
#private-bin bash
#private-bin python*
#private-bin xonsh
#private-bin cat
#private-bin ls
#private-bin nano

dbus-user none
dbus-system none

#env OLLAMA_LIBRARY_PATH=/usr/lib/ollama

join-or-start ollama_server_sandbox

#read-only ${HOME}
