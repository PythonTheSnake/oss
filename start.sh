#!/bin/bash

echo 'Hello,' $(uname -s)
python -mplatform

# Only Ubuntu supported at the moment
linux_deploy() {
  echo "Starting linux deployment!"
  apt-get update
  apt-get install -y python-dev python-pip build-essential
  pip install ansible
  mkdir -p /etc/ansible && echo "localhost" > /etc/ansible/hosts
  ansible-playbook -vv playbook.yml
}

cygwin_deploy() {
  echo "Sorry, Cygwin is not supported yet"
}

mac_deploy() {
  echo "Sorry, OS X is not supported yet. Try Vagrant"
  exit 1
# TODO:
#  check if brew is installed
#  install it if necessary
#  `brew install` rethinkdb, redis, etc
}


if [ "$(uname)" == "Darwin" ]; then
  mac_deploy
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  linux_deploy
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
  cygwin_deploy
fi
