#!/usr/bin/env bash
# Tests for skills/mig-pt-pt/scripts/check-pt.sh.
#
# Usage: bash tests/check-pt.test.sh

set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo/skills/mig-pt-pt/scripts/check-pt.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $label (expected $expected, got $actual)"
        sed 's/^/    /' "$tmp/out"
    fi
}
text() { printf '%s\n' "$1" | bash "$script" - >"$tmp/out" 2>&1; echo $?; }
has() { grep -q -- "$1" "$tmp/out" && echo yes || echo no; }

check "clean European text" 0 "$(text 'Guarde o ficheiro e inicie sessão. A carregar...')"
check "software words" 1 "$(text 'Salve o arquivo na tela')"
check "three hits on one line" 3 "$(grep -c -- '->' "$tmp/out")"
check "everyday words" 1 "$(text 'O mouse, o CEP, o trem e o suco')"
check "four everyday hits" 4 "$(grep -c -- '->' "$tmp/out")"
check "fato flagged" 1 "$(text 'Isso é um fato')"
check "endereço in a form flagged" 1 "$(text 'Endereço completo')"
check "endereço de email allowed" 0 "$(text 'Introduza o seu endereço de email')"
check "different systems flagged" 1 "$(text 'Emitimos a nota fiscal e o boleto')"
check "progressive flagged" 1 "$(text 'Estou fazendo o pedido')"
check "quando is not a gerund" 0 "$(text 'Estou quando posso')"
check "gerund with ellipsis flagged" 1 "$(text 'Carregando...')"
check "AI stock phrase flagged" 1 "$(text 'Em suma, vale ressaltar o resultado')"
check "whole words only" 0 "$(text 'Atelas, telhas e estelas')"
check "stdin named in output" yes "$(text 'usuário' >/dev/null; has '^stdin:1:usuário')"

mkdir -p "$tmp/lang/pt_PT" "$tmp/lang/pt_PT/vendor"
echo "'save' => 'Salvar'," > "$tmp/lang/pt_PT/app.php"
echo "'x' => 'deletar'," > "$tmp/lang/pt_PT/vendor/skip.php"
(cd "$tmp" && bash "$script") >"$tmp/out" 2>&1
check "default lang folder checked" 1 $?
check "file and line named" yes "$(has 'lang/pt_PT/app.php:1:Salvar')"
check "vendor skipped" no "$(has 'skip.php')"

(cd "$tmp/lang" && bash "$script") >"$tmp/out" 2>&1
check "nothing to check exits 2" 2 $?
bash "$script" "$tmp/missing" >"$tmp/out" 2>&1
check "missing target exits 2" 2 $?

echo "check-pt: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
