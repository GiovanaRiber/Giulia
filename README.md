# Giulia - Interpretador de Linguagem

![version](https://img.shields.io/badge/version-0.1.0-blue)
![language](https://img.shields.io/badge/language-Julia%20%2B%20Python-7957d5)
![julia](https://img.shields.io/badge/Julia-1.11%2B-brightgreen)
![antlr](https://img.shields.io/badge/ANTLR-4-orange)

Este projeto implementa um interpretador para a linguagem Giulia (.gl), baseada em um subconjunto de C. O processo ocorre em duas etapas:

1. **Parser Python (ANTLR)**: Analisa o código-fonte Giulia e gera uma AST simplificada em JSON
2. **Interpretador Julia**: Executa o código a partir da AST JSON gerada

## Arquitetura

```
Código Giulia (.gl)  →  [ANTLR Parser (Python)]  →  JSON AST  →  [Interpretador (Julia)]  →  Resultado
```

## Uso

### Forma Rápida (Script Automatizado)

```bash
./run_interpreter.sh exemplos/codigo.gl
```

### Forma Manual

1. Parse o código Giulia para JSON:
```bash
python src/parse_c.py exemplos/codigo.gl
```

2. Execute o interpretador Julia:
```bash
julia --project src/interprete.jl codigo_simplificado.json
```

## Funcionalidades Implementadas

### Tipos de Dados
- ✅ **int**: números inteiros
- ✅ **float**: números de ponto flutuante
- ✅ **char**: caracteres individuais (ex: `'A'`, `'b'`)
- ✅ **arrays**: arrays de tamanho fixo (ex: `int arr[5]`)
- ✅ **string**: literais de string (ex: "texto")

### Operadores

**Aritméticos**: `+`, `-`, `*`, `/`, `%`

**Relacionais**: `<`, `>`, `<=`, `>=`, `==`, `!=`

**Lógicos**: `!`, `&&`, `||`

### Estruturas de Controle

- ✅ **if / if-else**: condicionais simples e compostos
- ✅ **while**: laço com teste no início
- ✅ **do-while**: laço com teste no final
- ✅ **for**: laço com inicialização, condição e incremento
- ✅ **switch-case**: seleção múltipla com suporte a fall-through e break
- ✅ **return**: retorno de valores de funções
- ✅ **funções do usuário**: declaração, chamada e suporte à recursão

### Verificações em Tempo de Execução

- ✅ **Variáveis não declaradas**: detecta uso de variáveis não declaradas
- ✅ **Variáveis não inicializadas**: detecta leitura de variáveis declaradas mas não inicializadas
- ✅ **Array bounds checking**: detecta acessos fora dos limites do array
- ✅ **Verificação de tipos**: valida operações sobre tipos incompatíveis (ex: indexar não-array)
- ✅ **Operações aritméticas**: erro claro quando operandos não são numéricos
- ✅ **Atribuições numéricas**: `int/float` rejeitam valores não numéricos
- ✅ **Unions**: erro ao ler campo inativo (somente o campo "ativo" é válido)

### Tipos Compostos e Acesso a Campos

- ✅ **struct**: inicialização posicional, acesso e atribuição a campos (`.`/`->`)
- ✅ **union**: campo ativo controlado; atribuição ativa um campo e limpa os demais

### I/O e Utilidades

- ✅ **printf**, **puts**: saída
- ✅ **scanf**, **gets**: entrada
- ✅ **atoi**, **atof**: conversores de string (leem texto e retornam número)

### Pré-processamento (básico)

- ✅ **#define**: coleta e substituição simples de constantes
- ✅ **#include "arquivo"**: inclui arquivo relativo e mescla AST

## Exemplos

### Array Básico
```c
int main(void) {
    int arr[5];
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;
    arr[3] = arr[0] + arr[1];
    arr[4] = arr[2] * 2;
    
    int soma = arr[0] + arr[1] + arr[2] + arr[3] + arr[4];
    return soma;  // Resultado: 150
}
```

### Loop com Array
```c
int main(void) {
    int valores[3];
    valores[0] = 5;
    valores[1] = 10;
    valores[2] = 15;
    
    int i = 0;
    int resultado = 0;
    while (i < 3) {
        resultado = resultado + valores[i];
        i = i + 1;
    }
    
    return resultado;  // Resultado: 30
}
```

### Detecção de Erros

**Variável não inicializada:**
```c
int main(void) {
    int x;
    int y = x + 5;  // ERRO: Variável usada antes de inicialização: x
    return y;
}
```

**Índice fora dos limites:**
```c
int main(void) {
    int numeros[4];
    numeros[0] = 1;
    int acesso = numeros[5];  // ERRO: Índice fora do limite: 5
    return acesso;
}
```

**Leitura de campo inativo (union):**
```c
union U { int i; float f; };
int main(void) {
    union U u;
    u.f = 42.0;
    printf(u.i);  // ERRO: Leitura de campo inativo em union: ativo='f', lido='i'
    return 0;
}
```

## Estrutura do Projeto

```
Giulia/
├── src/
│   ├── interprete.jl        # Interpretador principal em Julia
│   ├── parse_c.py           # Parser ANTLR em Python
│   └── Giulia.jl            # Módulo Julia
├── gramatica/
│   ├── MiniC.g4             # Gramática ANTLR
│   └── MiniC*.py            # Arquivos gerados pelo ANTLR
├── exemplos/
│   ├── codigo.gl            # Exemplo básico
│   ├── teste_array.gl       # Arrays
│   ├── teste_array_loop.gl  # Arrays com loops
│   ├── teste_char.gl        # Caracteres
│   ├── teste_float.gl       # Floats
│   ├── teste_for.gl         # For loops
│   ├── teste_if.gl          # Condicionais
│   └── ...                  # Outros exemplos
├── run_interpreter.sh       # Script de execução automática
└── README.md
```

## Requisitos

- Python 3.x com `antlr4-python3-runtime`
- Julia 1.11+ com pacote `JSON`

## Instalação

1. Instale as dependências Python:
```bash
python -m venv .venv
source .venv/bin/activate  # ou .venv\Scripts\activate no Windows
pip install antlr4-python3-runtime
```

2. Instale Julia e o pacote JSON:
```bash
julia --project -e 'using Pkg; Pkg.add("JSON")'
```

## Limitações Conhecidas

- Não há suporte para ponteiros
- Strings são tratadas como literais, não como arrays de char mutáveis
- Não há pré-processador C real (apenas suporte básico a `#define` e `#include "..."`)
- Divisão `/` é inteira (comportamento simplificado)
- Inicializadores com designadores (ex: `{ .campo = valor }`) não são aceitos
- `#include <...>` (com ângulos) não é suportado; apenas `"arquivo"`

## Desenvolvimento

O projeto está em desenvolvimento ativo. Contribuições são bem-vindas!
