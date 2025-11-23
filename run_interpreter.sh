#!/bin/bash
# Script para executar o fluxo completo: Giulia (.gl) -> JSON -> Interpretador Julia

if [ $# -eq 0 ]; then
    echo "Uso: ./run_interpreter.sh <arquivo.gl>"
    echo "Exemplo: ./run_interpreter.sh exemplos/codigo.gl"
    exit 1
fi

ARQUIVO_GL="$1"

if [ ! -f "$ARQUIVO_GL" ]; then
    echo "Erro: Arquivo '$ARQUIVO_GL' não encontrado"
    exit 1
fi

echo "========================================"
echo "1. Parseando código Giulia com ANTLR..."
echo "========================================"
/workspaces/Giulia/.venv/bin/python src/parse_c.py "$ARQUIVO_GL"

if [ $? -ne 0 ]; then
    echo "Erro no parser"
    exit 1
fi

echo ""
echo "========================================"
echo "2. Interpretando com Julia..."
echo "========================================"
julia --project=. src/interprete.jl codigo_simplificado.json
