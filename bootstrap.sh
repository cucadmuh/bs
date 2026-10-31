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
umask 077
original_home=$HOME
tmp=$(mktemp -d)
netrc_tmp=
cleanup() {
    rm -rf "$tmp"
    if [ -n "$netrc_tmp" ]; then
        rm -f "$netrc_tmp"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -m 700 "$tmp/auth-home"

printf "\n\033[1;33mДоступ к репозиторию:\033[0m\n"
printf "Git запросит логин и пароль в терминале. После проверки они сохранятся в ~/.netrc для обновлений.\n"
printf "\nКлонирую репозиторий ...\n"
# Git reads credentials from /dev/tty, including when this script is piped to sh.
# Isolate authentication from stale .netrc files, helpers and askpass programs.
# Keep HOME unchanged for the installer by limiting these settings to a subshell.
if ! (
    unset GIT_ASKPASS SSH_ASKPASS
    export HOME="$tmp/auth-home"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=1
    git -c credential.helper= -c credential.helper=store clone --depth 1 \
        "https://git.misaev.ru/cucadmuh/antizlo.git/" "$tmp/repo"
); then
    printf "\033[0;31mОшибка клонирования. Проверьте логин/пароль.\033[0m\n"
    exit 1
fi

# --- persist the credentials Git successfully authenticated ---
# The isolated store helper captures successful authentication without putting
# passwords in clone URLs, command arguments or the environment.
printf 'protocol=https\nhost=git.misaev.ru\n\n' |
    git credential-store --file="$tmp/auth-home/.git-credentials" get > "$tmp/credentials"
user=
pass=
while IFS= read -r credential; do
    case "$credential" in
        username=*) user=${credential#username=} ;;
        password=*) pass=${credential#password=} ;;
    esac
done < "$tmp/credentials"
if [ -z "$user" ] || [ -z "$pass" ]; then
    printf "\033[0;31mНе удалось сохранить авторизацию для обновлений.\033[0m\n" >&2
    exit 1
fi

# libcurl supports quoted netrc fields, including escaped quotes/backslashes.
netrc_quote() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g'
}
netrc="$original_home/.netrc"
netrc_tmp=$(mktemp "$original_home/.netrc.XXXXXX")
{
    printf 'machine git.misaev.ru\nlogin "%s"\npassword "%s"\n\n' \
        "$(netrc_quote "$user")" "$(netrc_quote "$pass")"
    # The validated entry must precede stale entries. Keep existing records
    # intact, including any other accounts/hosts configured by the owner.
    if [ -f "$netrc" ]; then
        cat "$netrc"
    fi
} > "$netrc_tmp"
chmod 600 "$netrc_tmp"
mv -f "$netrc_tmp" "$netrc"
netrc_tmp=
unset user pass credential
# exec below skips EXIT traps; remove temporary credential files explicitly.
rm -f "$tmp/credentials" "$tmp/auth-home/.git-credentials"
rmdir "$tmp/auth-home"
printf "\033[0;32m✓ Проверенная авторизация сохранена в ~/.netrc (600) для обновлений\033[0m\n"

# --- run setup ---
setup="$tmp/repo/antizlo/bin/setup-alpine.sh"
if [ ! -f "$setup" ]; then
    printf "\033[0;31msetup-alpine.sh не найден в репозитории\033[0m\n"
    exit 1
fi

chmod +x "$setup"
export ANTIZLO_REPO_DIR="$tmp/repo/antizlo"
exec sh "$setup"
