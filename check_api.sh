#!/usr/bin/env bash
#
# check_api.sh – проверка доступности API по коду HTTP-ответа.
#
# Использование: ./check_api.sh <URL>
# Код возврата: 0 – API ответил 200, 1 – любой другой ответ или ошибка.

set -uo pipefail

readonly EXPECTED_CODE=200
readonly TIMEOUT=10

usage() {
    cat <<EOF
Использование: $(basename "$0") <URL>

Делает HTTP-запрос к URL и проверяет, что сервер вернул код ${EXPECTED_CODE}.

Примеры:
  $(basename "$0") https://httpbin.org/status/200
  $(basename "$0") http://localhost:80
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Ошибка: нужно передать ровно один аргумент – URL API" >&2
    usage >&2
    exit 1
fi

url="$1"

# Схема http(s), хост из букв, цифр, точек и дефисов,
# необязательный порт и путь
url_re='^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[^[:space:]]*)?$'
if [[ ! "$url" =~ $url_re ]]; then
    echo "Ошибка: некорректный URL: $url" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Ошибка: не найден curl" >&2
    exit 1
fi

# Тело ответа не нужно, забираем только код.
# Если соединиться не удалось, curl выводит 000
http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --max-time "$TIMEOUT" "$url")

if [[ "$http_code" == "$EXPECTED_CODE" ]]; then
    echo "API доступен"
    exit 0
fi

echo "API недоступен, код ответа: ${http_code}"
exit 1
