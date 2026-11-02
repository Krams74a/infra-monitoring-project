#!/usr/bin/env bash
#
# analyze_logs.sh – генерация тестового access.log и статистика по нему.
#
# Использование: ./analyze_logs.sh [-n СТРОК] [-f ФАЙЛ] [-s] [-h]

set -euo pipefail

readonly MIN_LINES=300

lines=300
log_file="access.log"
generate=true

# IPv4-адрес в начале строки: четыре октета от 0 до 255
readonly OCTET='(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
readonly IP_RE="^(${OCTET}\\.){3}${OCTET}"

usage() {
    cat <<EOF
Использование: $(basename "$0") [-n СТРОК] [-f ФАЙЛ] [-s] [-h]

Генерирует тестовый лог веб-сервера и выводит по нему статистику:
общее число запросов, топ-3 IP-адресов, число ответов 4xx и 5xx.

  -n СТРОК  сколько строк сгенерировать
            (по умолчанию ${lines}, не меньше ${MIN_LINES})
  -f ФАЙЛ   путь к файлу лога (по умолчанию ${log_file})
  -s        не генерировать лог, а только проанализировать существующий файл
  -h        показать эту справку
EOF
}

die() {
    echo "Ошибка: $*" >&2
    exit 1
}

generate_log() {
    local file="$1" count="$2"

    # Повторы в списках задают веса: одни IP, запросы и коды
    # встречаются чаще других
    local ips=(
        192.168.1.10 192.168.1.10 192.168.1.10
        192.168.1.10 192.168.1.10 192.168.1.10
        10.0.0.5 10.0.0.5 10.0.0.5 10.0.0.5 10.0.0.5
        172.16.0.23 172.16.0.23 172.16.0.23 172.16.0.23
        192.168.1.15 192.168.1.15 192.168.1.15
        10.0.0.8 10.0.0.8
        203.0.113.7 198.51.100.42 192.168.1.20
    )
    local requests=(
        "GET /api/users" "GET /api/users" "GET /api/users" "GET /api/users/42"
        "GET /api/orders" "GET /api/orders" "GET /health"
        "POST /api/login" "POST /api/login" "POST /api/orders"
        "PUT /api/users/42" "DELETE /api/orders/7"
    )
    local codes=(
        200 200 200 200 200 200 200 200 200 200 200 200
        201 204 301 400 401 401 403 404 404 500 502 503
    )

    local ts=$(( 10 * 3600 + 15 * 60 ))   # время первой записи – 10:15:00
    local i ip req code

    # Фиксированное зерно: лог получается одинаковым от запуска к запуску
    RANDOM=2026
    for (( i = 0; i < count; i++ )); do
        ip=${ips[RANDOM % ${#ips[@]}]}
        req=${requests[RANDOM % ${#requests[@]}]}
        code=${codes[RANDOM % ${#codes[@]}]}
        printf '%s - - [15/Aug/2026:%02d:%02d:%02d] "%s HTTP/1.1" %s\n' \
            "$ip" $(( ts / 3600 % 24 )) $(( ts / 60 % 60 )) $(( ts % 60 )) \
            "$req" "$code"
        ts=$(( ts + RANDOM % 4 ))
    done > "$file"
}

analyze_log() {
    local file="$1"
    local total c4xx c5xx

    # Запросом считаем строку, которая начинается с корректного IP-адреса
    total=$(grep -cE "$IP_RE" "$file" || true)

    echo "=== Анализ лога: ${file} ==="
    echo "Общее количество запросов: ${total}"
    echo

    echo "Топ-3 IP-адресов по числу запросов:"
    grep -oE "$IP_RE" "$file" | sort | uniq -c | sort -rn |
        awk 'NR <= 3 { printf "  %d. %-15s %d\n", NR, $2, $1 }'
    echo

    # Код ответа – последнее поле строки
    read -r c4xx c5xx < <(awk '
        $NF ~ /^4[0-9][0-9]$/ { c4++ }
        $NF ~ /^5[0-9][0-9]$/ { c5++ }
        END { print c4 + 0, c5 + 0 }
    ' "$file")
    echo "Запросы с кодами ошибок:"
    echo "  4xx (ошибки клиента): ${c4xx}"
    echo "  5xx (ошибки сервера): ${c5xx}"
    echo

    echo "Запросы по HTTP-методам:"
    sed -nE 's/^[^"]*"([A-Z]+) [^"]*".*$/\1/p' "$file" |
        sort | uniq -c | sort -rn |
        awk '{ printf "  %-7s %d\n", $2, $1 }'
}

while getopts ":n:f:sh" opt; do
    case "$opt" in
        n) lines="$OPTARG" ;;
        f) log_file="$OPTARG" ;;
        s) generate=false ;;
        h) usage; exit 0 ;;
        :) usage >&2; die "для ключа -${OPTARG} нужно значение" ;;
        \?) usage >&2; die "неизвестный ключ -${OPTARG}" ;;
    esac
done
shift $(( OPTIND - 1 ))

if [[ $# -gt 0 ]]; then
    usage >&2
    die "лишние аргументы: $*"
fi

for tool in grep awk sed sort uniq; do
    command -v "$tool" >/dev/null 2>&1 || die "не найдена утилита ${tool}"
done

if [[ "$generate" == true ]]; then
    if [[ ! "$lines" =~ ^[0-9]+$ ]] || (( 10#$lines < MIN_LINES )); then
        die "значение -n должно быть целым числом не меньше ${MIN_LINES}"
    fi
    generate_log "$log_file" "$(( 10#$lines ))"
    echo "Сгенерирован файл ${log_file}: $(wc -l < "$log_file") строк"
    echo
fi

[[ -f "$log_file" ]] || die "файл ${log_file} не найден"
[[ -s "$log_file" ]] || die "файл ${log_file} пустой"

analyze_log "$log_file"
