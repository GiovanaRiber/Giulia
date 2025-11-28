# src/interprete.jl - VERSÃO FINAL (COMPLETA)
using JSON

# Tabela de funções
const tabela_de_funcoes = Dict{String, Any}()

# Função que calcula o valor de uma expressão
function avaliar_expressao(expr_json, env)
    
    # Literal
    if isa(expr_json, Number) return expr_json end

    # Variável
    if isa(expr_json, String)
        if haskey(env, expr_json)
            val = env[expr_json]
            if isnothing(val) error("Variável usada antes de inicialização: $expr_json") end
            return val
        else
            error("Variável não declarada ou fora de escopo: $expr_json")
        end
    end

    # Nós compostos
    if isa(expr_json, AbstractDict)
        t = get(expr_json, "type", nothing)

        if t == "String" || t == "Char"
            return expr_json["value"]

        # Unário (!, -, +)
        elseif t == "UnaryOp"
            op = expr_json["op"]
            val = avaliar_expressao(expr_json["expr"], env)
            
            if op == "!"  
                return (val == 0 || val == false) ? 1 : 0
            elseif op == "-" 
                return -val
            elseif op == "+" 
                return val
            else 
                error("Operador unário não suportado: $op") 
            end

        # Binário
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

        # Chamada de função
        elseif t == "Call"
            func_name = expr_json["callee"]
            args_exprs = expr_json["args"]
            vals_args = [avaliar_expressao(arg, env) for arg in args_exprs]

            # Nativas
            if func_name == "printf"
                for v in vals_args print(v, " ") end
                println("")
                return 0

            elseif func_name == "puts"
                if length(vals_args) > 0 println(vals_args[1]) else println("") end
                return 0

            elseif func_name == "atoi"
                if length(vals_args) != 1
                    error("Função atoi espera 1 argumento")
                end
                s = vals_args[1]
                if !(s isa String)
                    error("atoi: argumento deve ser String, recebido $(typeof(s))")
                end
                v = tryparse(Int, s)
                if isnothing(v)
                    error("atoi: entrada inválida: \"$s\"")
                end
                return v

            elseif func_name == "atof"
                if length(vals_args) != 1
                    error("Função atof espera 1 argumento")
                end
                s = vals_args[1]
                if !(s isa String)
                    error("atof: argumento deve ser String, recebido $(typeof(s))")
                end
                v = tryparse(Float64, s)
                if isnothing(v)
                    error("atof: entrada inválida: \"$s\"")
                end
                return v

            elseif func_name == "scanf" || func_name == "gets"
                input_str = readline()
                
                if func_name == "gets"
                    return input_str
                else
                    val = tryparse(Int, input_str)
                    if isnothing(val) val = tryparse(Float64, input_str) end
                    if isnothing(val) val = input_str end
                    return val
                end
            end

            # Função do usuário
            if !haskey(tabela_de_funcoes, func_name)
                error("Função não definida: $func_name")
            end
            return executar_funcao_logica(tabela_de_funcoes[func_name], vals_args)

        # Acesso a array
        elseif t == "ArrayAccess"
            arr_node = expr_json["array"]
            idx = avaliar_expressao(expr_json["index"], env)
            arr_ref = isa(arr_node, String) ? env[arr_node] : avaliar_expressao(arr_node, env)
            
            if !(arr_ref isa AbstractVector) error("Não é um array: $arr_node") end
            i = Int(idx)
            if i < 0 || i+1 > length(arr_ref) error("Índice fora do limite: $i") end
            return arr_ref[i+1]

        # Acesso a campo
        elseif t == "FieldAccess"
            obj_node = expr_json["object"]
            field = expr_json["field"]
            obj_val = isa(obj_node, String) ? env[obj_node] : avaliar_expressao(obj_node, env)
            if obj_val isa Dict{String,Any}
                if !haskey(obj_val, field)
                    error("Campo '$field' inexistente")
                end
                return obj_val[field]
            end
            error("Acesso de campo em tipo não suportado")
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

# Executa um statement
function executar_statement(stmt, env)
    stmt_type = get(stmt, "type", nothing)

    if stmt_type == "Declaration"
        var_name = stmt["name"]
        val_expr = get(stmt, "value", nothing)
        tipo_declarado = get(stmt, "varType", "int")
        
        # Guardar tipo para uso futuro (opcional)
        # tabela_de_tipos[var_name] = tipo_declarado 

        if get(stmt, "isArray", false)
            size = stmt["size"]
            env[var_name] = zeros(Int, size)
            if !isnothing(val_expr) && isa(val_expr, Array)
                for (i, v) in enumerate(val_expr)
                     env[var_name][i] = avaliar_expressao(v, env)
                end
            end
        else
            if !isnothing(val_expr)
                if isa(val_expr, AbstractDict) && !haskey(val_expr, "type")
                    novo = Dict{String,Any}()
                    for (k,v) in val_expr
                        if k == "_active"
                            novo[k] = v
                        else
                            novo[string(k)] = avaliar_expressao(v, env)
                        end
                    end
                    env[var_name] = novo
                else
                    valor_bruto = avaliar_expressao(val_expr, env)
                    
                    if tipo_declarado == "int"
                        if isa(valor_bruto, Number)
                            env[var_name] = Int(floor(valor_bruto))
                        else
                            env[var_name] = valor_bruto # Deixa passar se não for número
                        end
                    elseif tipo_declarado == "float" || tipo_declarado == "double"
                        env[var_name] = Float64(valor_bruto)
                    elseif tipo_declarado == "char"
                        env[var_name] = valor_bruto
                    else
                        env[var_name] = valor_bruto
                    end
                end
            else
                env[var_name] = nothing
            end
        end

    elseif stmt_type == "Assignment"
        target = stmt["name"]
        valor = avaliar_expressao(stmt["value"], env)

        if isa(target, AbstractDict) && get(target, "type", nothing) == "ArrayAccess"
            nome_arr = target["array"]
            idx = avaliar_expressao(target["index"], env)
            env[nome_arr][idx + 1] = valor
        elseif isa(target, AbstractDict) && get(target, "type", nothing) == "FieldAccess"
            obj_node = target["object"]
            field = target["field"]
            obj_val = isa(obj_node, String) ? env[obj_node] : avaliar_expressao(obj_node, env)
            if !(obj_val isa Dict{String,Any})
                error("Atribuição em campo de tipo não suportado")
            end
            # Se for uma union representada com campo ativo, zera demais
            if haskey(obj_val, "_active")
                # Limpa outros campos
                for k in keys(obj_val)
                    if k != field && k != "_active"
                        obj_val[k] = nothing
                    end
                end
                obj_val[field] = valor
                obj_val["_active"] = field
            else
                obj_val[field] = valor
            end
        else
            env[target] = valor
        end

    elseif stmt_type == "Call"
        avaliar_expressao(stmt, env)

    elseif stmt_type == "Return"
        return avaliar_expressao(stmt["value"], env)

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

    elseif stmt_type == "DoWhile"
        while true
            ret = executar_statements(stmt["body"], env)
            if !isnothing(ret) return ret end
            cond_val = avaliar_expressao(stmt["condition"], env)
            if cond_val == 0 || cond_val == false
                break
            end
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

# Executa uma função
function executar_funcao_logica(func_json, args_values=[])
    nome = func_json["name"]
    tipo_retorno = get(func_json, "returnType", "int")

    # Escopo local
    local_env = Dict{String, Any}()
    
    # Argumentos
    param_names = get(func_json, "params", String[])
    if length(args_values) != length(param_names)
        error("Erro na chamada de '$nome': Esperava $(length(param_names)) argumentos.")
    end
    for i in 1:length(param_names)
        local_env[param_names[i]] = args_values[i]
    end
    
    # Executa corpo
    ret = executar_statements(func_json["body"], local_env)
    
    # Retorno void
    if tipo_retorno == "void"
        return nothing
    end

    # Padrão C: 0 se não retornou
    return isnothing(ret) ? 0 : ret
end

function main()
    if length(ARGS) != 1
        println("Uso: julia src/interprete.jl <json>")
        return
    end
    
    ast = JSON.parsefile(ARGS[1])
    println("Carregando funções...")
    for func in ast
        if func["type"] == "Function"
            tabela_de_funcoes[func["name"]] = func
        end
    end
    
    if haskey(tabela_de_funcoes, "main")
        println("\nExecução Iniciada")
        try
            res = executar_funcao_logica(tabela_de_funcoes["main"])
            println("\nResultado Final: $res")
        catch e
            # Erro amigável
            if e isa MethodError
                funcname = try string(getfield(e, :f)) catch; "função" end
                argtypes = try join([string(typeof(a)) for a in getfield(e, :args)], ", ") catch; "tipos desconhecidos" end
                println("\nErro: Operação inválida: $(funcname) com argumentos de tipos ($(argtypes))")
            elseif e isa ErrorException
                println("\nErro: $(getfield(e, :msg))")
            else
                println("\nErro: $(e)")
            end
        end
    else
        println("Erro: Função 'main' não encontrada.")
    end
end

main()