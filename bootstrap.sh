#!/bin/sh
set -eu

printf "\033[0;34m=== Установка ===\033[0m\n\n"

# --- community repo ---
repos="/etc/apk/repositories"
if ! grep -q "^[^#].*community" "$repos" 2>/dev/null; then
    printf "\033[1;33mcommunity-репозиторий не подключен.\033[0m\n"
    main_mirror=$(grep -m1 '^http.*main$' "$repos" | sed 's|/main$||')
    if [ -n "$main_mirror" ]; then
        printf "Добавляю %s/community ...\n" "$main_mirror"
        echo "${main_mirror}/community" >> "$repos"
        apk update >/dev/null 2>&1
    else
        printf "\033[0;31mНе удалось определить зеркало. Добавьте community вручную.\033[0m\n"
        exit 1
    fi
fi

# --- git ---
if ! command -v git >/dev/null 2>&1; then
    printf "Устанавливаю git ...\n"
    apk add git >/dev/null 2>&1
fi

# --- clone ---
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -m 700 "$tmp/auth-home"

printf "\n\033[1;33mДоступ к репозиторию:\033[0m\n"
printf "Git запросит логин и пароль в терминале; пароль не сохраняется.\n"
printf "\nКлонирую репозиторий ...\n"
# Git reads credentials from /dev/tty, including when this script is piped to sh.
# Isolate authentication from stale .netrc files, helpers and askpass programs.
# Keep HOME unchanged for the installer by limiting these settings to a subshell.
if ! (
    unset GIT_ASKPASS SSH_ASKPASS
    export HOME="$tmp/auth-home"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=1
    git -c credential.helper= clone --depth 1 \
        "https://git.misaev.ru/cucadmuh/antizlo.git/" "$tmp/repo"
); then
    printf "\033[0;31mОшибка клонирования. Проверьте логин/пароль.\033[0m\n"
    exit 1
fi

# --- run setup ---
setup="$tmp/repo/antizlo/bin/setup-alpine.sh"
if [ ! -f "$setup" ]; then
    printf "\033[0;31msetup-alpine.sh не найден в репозитории\033[0m\n"
    exit 1
fi

chmod +x "$setup"
export ANTIZLO_REPO_DIR="$tmp/repo/antizlo"
exec sh "$setup"
