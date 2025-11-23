# src/interprete.jl - VERSÃO FINAL (COMPLETA)
using JSON

# Guarda as definições das funções
const tabela_de_funcoes = Dict{String, Any}()

# Função que calcula o valor de uma expressão
function avaliar_expressao(expr_json, env)
    
    # Caso 1: Literal
    if isa(expr_json, Number) return expr_json end

    # Caso 2: Variável
    if isa(expr_json, String)
        if haskey(env, expr_json)
            val = env[expr_json]
            if isnothing(val) error("Variável usada antes de inicialização: $expr_json") end
            return val
        else
            error("Variável não declarada ou fora de escopo: $expr_json")
        end
    end

    # Caso 3: Objetos complexos
    if isa(expr_json, AbstractDict)
        t = get(expr_json, "type", nothing)

        if t == "String" || t == "Char"
            return expr_json["value"]

        # --- OPERADORES UNÁRIOS (!, -) ---
        elseif t == "UnaryOp"
            op = expr_json["op"]
            val = avaliar_expressao(expr_json["expr"], env)
            
            if op == "!"  
                # Negação Lógica (0 -> 1, Outros -> 0)
                return (val == 0 || val == false) ? 1 : 0
            elseif op == "-" 
                return -val
            elseif op == "+" 
                return val
            else 
                error("Operador unário não suportado: $op") 
            end

        # --- OPERADORES BINÁRIOS ---
        elseif t == "BinaryOp"
            op = expr_json["op"]
            left = avaliar_expressao(expr_json["left"], env)
            right = avaliar_expressao(expr_json["right"], env)

            if op == "+" return left + right
            elseif op == "-" return left - right
            elseif op == "*" return left * right
            elseif op == "/" return div(left, right) # Divisão inteira
            elseif op == "%" return left % right     # Módulo
            elseif op == ">" return left > right
            elseif op == "<" return left < right
            elseif op == ">=" return left >= right
            elseif op == "<=" return left <= right
            elseif op == "==" return left == right
            elseif op == "!=" return left != right
            elseif op == "&&" return (left!=0) && (right!=0)
            elseif op == "||" return (left!=0) || (right!=0)
            else error("Operador desconhecido: $op") end

        # --- CHAMADA DE FUNÇÃO (COM I/O) ---
        elseif t == "Call"
            func_name = expr_json["callee"]
            args_exprs = expr_json["args"]
            vals_args = [avaliar_expressao(arg, env) for arg in args_exprs]

            # Funções Nativas (I/O)
            if func_name == "printf"
                print("💻 ")
                for v in vals_args print(v, " ") end
                println("")
                return 0

            elseif func_name == "puts"
                print("💻 ")
                if length(vals_args) > 0 println(vals_args[1]) else println("") end
                return 0

            elseif func_name == "scanf" || func_name == "gets"
                print("⌨️  ")
                input_str = readline()
                
                if func_name == "gets"
                    return input_str
                else
                    # Scanf tenta converter
                    val = tryparse(Int, input_str)
                    if isnothing(val) val = tryparse(Float64, input_str) end
                    if isnothing(val) val = input_str end
                    return val
                end
            end

            # Chamada de Função do Usuário
            if !haskey(tabela_de_funcoes, func_name)
                error("Função não definida: $func_name")
            end
            return executar_funcao_logica(tabela_de_funcoes[func_name], vals_args)

        # --- ACESSO A ARRAY ---
        elseif t == "ArrayAccess"
            arr_node = expr_json["array"]
            idx = avaliar_expressao(expr_json["index"], env)
            arr_ref = isa(arr_node, String) ? env[arr_node] : avaliar_expressao(arr_node, env)
            
            if !(arr_ref isa AbstractVector) error("Não é um array: $arr_node") end
            i = Int(idx)
            if i < 0 || i+1 > length(arr_ref) error("Índice fora do limite: $i") end
            return arr_ref[i+1]
        end
    end
    error("Expressão desconhecida: $expr_json")
end

# Executa uma lista de statements
function executar_statements(statements, env)
    for stmt in statements
        ret = executar_statement(stmt, env)
        if !isnothing(ret) return ret end
    end
    return nothing
end

# Executa um statement individual
function executar_statement(stmt, env)
    stmt_type = get(stmt, "type", nothing)

    if stmt_type == "Declaration"
        var_name = stmt["name"]
        val_expr = get(stmt, "value", nothing)
        tipo_declarado = get(stmt, "varType", "int") # Padrão int se não especificado
        
        # Guardar tipo para uso futuro (opcional)
        # tabela_de_tipos[var_name] = tipo_declarado 

        if get(stmt, "isArray", false)
            # ... (Lógica de array igual) ...
            size = stmt["size"]
            env[var_name] = zeros(Int, size)
            if !isnothing(val_expr) && isa(val_expr, Array)
                for (i, v) in enumerate(val_expr)
                     env[var_name][i] = avaliar_expressao(v, env)
                end
            end
        else
            # --- CORREÇÃO DE TIPOS (CASTING) ---
            if !isnothing(val_expr)
                valor_bruto = avaliar_expressao(val_expr, env)
                
                # Conversão forçada baseada no tipo C
                if tipo_declarado == "int"
                    # Se for float (ex: 5.5), trunca para Int (5)
                    # Se for string ou char, tenta converter
                    if isa(valor_bruto, Number)
                        env[var_name] = Int(floor(valor_bruto))
                    else
                        env[var_name] = valor_bruto # Deixa passar se não for número
                    end
                elseif tipo_declarado == "float" || tipo_declarado == "double"
                    env[var_name] = Float64(valor_bruto)
                elseif tipo_declarado == "char"
                    # Assume que já é char ou string
                    env[var_name] = valor_bruto
                else
                    # Outros tipos
                    env[var_name] = valor_bruto
                end
            else
                env[var_name] = nothing
            end
            # -----------------------------------
        end

    elseif stmt_type == "Assignment"
        target = stmt["name"]
        valor = avaliar_expressao(stmt["value"], env)

        if isa(target, AbstractDict) && get(target, "type", nothing) == "ArrayAccess"
            nome_arr = target["array"]
            idx = avaliar_expressao(target["index"], env)
            env[nome_arr][idx + 1] = valor
        else
            # Aqui poderíamos checar o tipo da variável já existente para forçar conversão também
            # Mas vamos simplificar e permitir troca dinâmica por enquanto
            env[target] = valor
        end

    elseif stmt_type == "Call"
        avaliar_expressao(stmt, env)

    elseif stmt_type == "Return"
        return avaliar_expressao(stmt["value"], env)

    # ... (Os blocos If, While, For, Switch continuam IGUAIS ao código anterior) ...
    elseif stmt_type == "If" || stmt_type == "IfElse"
        cond = avaliar_expressao(stmt["condition"], env)
        if cond == true || cond != 0
            return executar_statements(stmt["thenBody"], env)
        elseif stmt_type == "IfElse"
            return executar_statements(stmt["elseBody"], env)
        end

    elseif stmt_type == "While"
        while avaliar_expressao(stmt["condition"], env) != 0
            ret = executar_statements(stmt["body"], env)
            if !isnothing(ret) return ret end
        end

    elseif stmt_type == "For"
        if !isnothing(get(stmt, "init", nothing))
            executar_statement(stmt["init"], env)
        end
        while isnothing(get(stmt, "condition", nothing)) || (avaliar_expressao(stmt["condition"], env) != 0)
            ret = executar_statements(stmt["body"], env)
            if !isnothing(ret) return ret end
            
            if !isnothing(get(stmt, "increment", nothing))
                incr = stmt["increment"]
                if isa(incr, AbstractDict) && get(incr, "type", nothing) == "Assignment"
                    target = incr["name"]
                    val = avaliar_expressao(incr["value"], env)
                    env[target] = val
                else
                    try executar_statement(incr, env) catch; avaliar_expressao(incr, env) end
                end
            end
        end

    elseif stmt_type == "Switch"
        val_switch = avaliar_expressao(stmt["value"], env)
        executar = false
        for caso in stmt["cases"]
            match = false
            if caso["type"] == "Case"
                if val_switch == avaliar_expressao(caso["value"], env) match = true end
            elseif caso["type"] == "Default"
                match = true 
            end

            if match || executar
                executar = true
                ret = executar_statements(caso["body"], env)
                if !isnothing(ret) return ret end
                if get(caso, "hasBreak", false) break end
            end
        end
    end
    return nothing
end

# Cria escopo e executa função
function executar_funcao_logica(func_json, args_values=[])
    nome = func_json["name"]
    tipo_retorno = get(func_json, "returnType", "int") # Pega o tipo de retorno

    # 1. Cria Escopo
    local_env = Dict{String, Any}()
    
    # 2. Argumentos
    param_names = get(func_json, "params", String[])
    if length(args_values) != length(param_names)
        error("Erro na chamada de '$nome': Esperava $(length(param_names)) argumentos.")
    end
    for i in 1:length(param_names)
        local_env[param_names[i]] = args_values[i]
    end
    
    # 3. Executa
    ret = executar_statements(func_json["body"], local_env)
    
    # 4. Tratamento do Retorno VOID
    if tipo_retorno == "void"
        # Se for void, retornamos 'nothing' (ou 0 se preferir, mas 'nothing' é mais correto semanticamente)
        return nothing
    end

    # Se não for void e não retornou nada, retornamos 0 (padrão C)
    return isnothing(ret) ? 0 : ret
end

function main()
    if length(ARGS) != 1
        println("Uso: julia src/interprete.jl <json>")
        return
    end
    
    ast = JSON.parsefile(ARGS[1])
    println("📦 Carregando funções...")
    for func in ast
        if func["type"] == "Function"
            tabela_de_funcoes[func["name"]] = func
        end
    end
    
    if haskey(tabela_de_funcoes, "main")
        println("\n🚀 Execução Iniciada")
        res = executar_funcao_logica(tabela_de_funcoes["main"])
        println("\n✅ Resultado Final: $res")
    else
        println("❌ Erro: Função 'main' não encontrada.")
    end
end

main()