#!/bin/bash

export USER_ID=${LOCAL_USER_ID:-9001}
# export GROUP_ID=${LOCAL_USER_ID}
# groupmod -g "$GROUP_ID" ampuser
# usermod -u "$USER_ID" -o -c "" ampuser
# usermod -u "$USER_ID" -o -c "" ampuser
# usermod -u "$USER_ID" -g "$USER_ID" -o -c "" ampuser
useradd --shell /bin/bash -u "$USER_ID" -o -c "" -m ampuser
export HOME="/home/ampuser"

exec /usr/sbin/gosu ampuser "$@"
