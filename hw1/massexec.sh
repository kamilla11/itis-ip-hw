#!/usr/bin/env bash
# Задача 6. Массовая обработка файлов

usage() {
    printf 'Использование: %s [--path dirpath] [--mask mask] [--number number] command\n' "$0" >&2
}
fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 2; }

path='.'
mask='*'
number=$(nproc)
while (($# > 0)); do
    case "$1" in
        --path|--mask|--number)
            (($# >= 2)) || { usage; exit 2; }
            case "$1" in
                --path) path=$2 ;;
                --mask) mask=$2 ;;
                --number) number=$2 ;;
            esac
            shift 2 ;;
        --*) usage; exit 2 ;;
        *) break ;;
    esac
done
(($# == 1)) || { usage; exit 2; }
command_name=$1
[[ -d $path ]] || fail "каталог '$path' не существует"
[[ -n $mask ]] || fail 'маска не должна быть пустой'
[[ $number =~ ^[0-9]+$ ]] && ((10#$number > 0)) || fail 'число процессов должно быть больше нуля'
number=$((10#$number))

if [[ $command_name == */* ]]; then
    command_path=$command_name
else
    command_path=$(type -P -- "$command_name") || fail "команда '$command_name' не найдена"
fi
[[ -f $command_path && -x $command_path ]] || fail "команда '$command_name' не является исполняемым файлом"

absolute_dir=$(cd -- "$path" && pwd -P) || fail "не удалось открыть '$path'"
files=()
while IFS= read -r -d '' file; do
    basename=${file##*/}
    if [[ $basename == $mask ]]; then
        files+=("$file")
    fi
done < <(find "$absolute_dir" -mindepth 1 -maxdepth 1 -type f -print0)

declare -A active=()
failed=0
wait_for_slot() {
    local finished='' status=0 pid
    if wait -n -p finished "${!active[@]}"; then
        status=0
    else
        status=$?
    fi
    if [[ -n $finished ]]; then
        unset "active[$finished]"
        ((status == 0)) || failed=1
    else
        for pid in "${!active[@]}"; do
            wait "$pid" || failed=1
            unset "active[$pid]"
        done
    fi
}

for file in "${files[@]}"; do
    while ((${#active[@]} >= number)); do
        wait_for_slot
    done
    "$command_path" "$file" &
    active[$!]=1
done
while ((${#active[@]} > 0)); do
    wait_for_slot
done
exit "$failed"
