#!/bin/bash

USER_ID=${LOCAL_USER_ID:-9001}
useradd --shell /bin/bash -u "$USER_ID" -o -c "" -m ampuser
export HOME="/home/ampuser"

exec /usr/sbin/gosu ampuser "$@"
