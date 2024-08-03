#!/bin/sh
set -e

log() {
  echo ">> [local]" $@
}

cleanup() {
  set +e
  log "Killing ssh agent."
  ssh-agent -k
  log "Removing workspace archive."
  rm -f /tmp/$SERVICE_PREFIX.deploy.tar.bz2
}
trap cleanup EXIT

log "Packing yaml into archive to transfer onto remote machine."
tar cjvf /tmp/$SERVICE_PREFIX.deploy.tar.bz2 --exclude .git --exclude vendor $YAML_SOURCE_PATH

log "Launching ssh agent."
eval `ssh-agent -s`

remote_command="
  set -e ;
  log() { echo '>> [remote]' \$@ ; } ;
  cleanup() { log 'Removing yaml archive...'; rm -f \"\$HOME/workspace/$SERVICE_PREFIX.deploy.tar.bz2\" ; } ;
  log 'Creating workspace directory...' ;
  mkdir -p \"\$HOME/workspace/$SERVICE_PREFIX\" ;
  trap cleanup EXIT ;
  log 'Unpacking workspace...' ;
  tar -C \"\$HOME/workspace/$SERVICE_PREFIX\" -xjv ;
  log 'Launching docker stack deploy...' ;
  cd \"\$HOME/workspace/$SERVICE_PREFIX\" ; 
  # docker stack deploy -c \"$YAML_FILENAME\" --prune \"$SERVICE_PREFIX\"
"

# Проверяем, что переменная SSH_PRIVATE_KEY не пустая
if [ -z "$SSH_PRIVATE_KEY" ]; then
  log "SSH_PRIVATE_KEY is empty. Please provide a valid SSH private key."
  exit 1
fi


# Создаем временный файл для приватного ключа
tmp_key=$(mktemp)
echo "$SSH_PRIVATE_KEY" > "$tmp_key"

# Проверяем содержимое временного файла (не забудьте удалить после проверки)
log "Private key:"
cat "$tmp_key"
log "Adding private key to ssh-agent"
ssh-add "$tmp_key"

# Удаляем временный файл
rm "$tmp_key"

echo ">> [local] Connecting to remote host."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" \
  "$remote_command" \
  < /tmp/$SERVICE_PREFIX.deploy.tar.bz2
