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

# --- credentials (read from /dev/tty for pipe compatibility) ---
printf "\n\033[1;33mДоступ к репозиторию:\033[0m\n"
printf "Логин: "; read -r user </dev/tty
printf "Пароль: "; stty -F /dev/tty -echo; read -r pass </dev/tty; stty -F /dev/tty echo; printf "\n"

repo_url="https://${user}:${pass}@git.misaev.ru/cucadmuh/antizlo.git"

# --- clone ---
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

printf "\nКлонирую репозиторий ...\n"
if ! git clone --depth 1 "$repo_url" "$tmp/repo" 2>&1 | grep -v '^$'; then
    printf "\033[0;31mОшибка клонирования. Проверьте логин/пароль.\033[0m\n"
    exit 1
fi

# --- .netrc ---
netrc="$HOME/.netrc"
if ! grep -q "git.misaev.ru" "$netrc" 2>/dev/null; then
    printf "machine git.misaev.ru\nlogin %s\npassword %s\n" "$user" "$pass" >> "$netrc"
    chmod 600 "$netrc"
    printf "\033[0;32m✓ Настроен .netrc для будущих git-операций\033[0m\n"
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
