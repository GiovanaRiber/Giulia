import sys
import os
import json
import re
from antlr4 import *

script_dir = os.path.dirname(__file__)
grammar_dir = os.path.join(script_dir, '..', 'gramatica')
sys.path.append(os.path.abspath(grammar_dir))

from MiniCLexer import MiniCLexer
from MiniCParser import MiniCParser
from MiniCVisitor import MiniCVisitor

class AstVisitor(MiniCVisitor):

    def __init__(self):
        self.defines = {}
        self.struct_defs = {}
        self.union_defs = {}

    def visitCompilationUnit(self, ctx:MiniCParser.CompilationUnitContext):
        resultados = []
        for i in range(ctx.getChildCount()):
            child = ctx.getChild(i)
            if isinstance(child, MiniCParser.ExternalDeclarationContext):
                resultado_visit = self.visit(child)
                if resultado_visit:
                    resultados.append(resultado_visit)
            elif isinstance(child, TerminalNode):
                text = child.getText().strip()
                if text.startswith("#define"):
                    self.processarDefine(text)
        return resultados

    def processarDefine(self, text):
        match = re.match(r'#\s*define\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+(.*)', text)
        if match:
            name = match.group(1)
            value_str = match.group(2).strip()
            try:
                if '.' in value_str: value = float(value_str)
                else: value = int(value_str)
            except:
                value = value_str
            self.defines[name] = value
            print(f"🔹 Pré-processador: Definido {name} = {value}")

    # Função: coleta nome, retorno e params
    def visitFunctionDefinition(self, ctx:MiniCParser.FunctionDefinitionContext):
        return_type = self.visit(ctx.typeSpecifier())
        
        # Aux: nome e parâmetros
        def get_name_and_params(direct_decl_ctx):
            name = None
            params = []
            
            # Parâmetros no nível atual
            if direct_decl_ctx.parameterTypeList():
                p_list = direct_decl_ctx.parameterTypeList().parameterList()
                for p in p_list.parameterDeclaration():
                    # Nome do parâmetro
                    p_decl = p.declarator()
                    p_direct = p_decl.directDeclarator()
                    # Desce até o identificador
                    while p_direct.directDeclarator():
                        p_direct = p_direct.directDeclarator()
                    params.append(p_direct.Identifier().getText())
            
            # Nome local ou do filho
            if direct_decl_ctx.Identifier():
                name = direct_decl_ctx.Identifier().getText()
            elif direct_decl_ctx.directDeclarator():
                # Recursão
                child_name, child_params = get_name_and_params(direct_decl_ctx.directDeclarator())
                if child_name: name = child_name
                if child_params: params = child_params
            
            return name, params

        # Busca
        decl_ctx = ctx.declarator().directDeclarator()
        name, params = get_name_and_params(decl_ctx)
        
        body = self.visit(ctx.compoundStatement())
        
        return {
            "type": "Function",
            "name": name,
            "returnType": return_type,
            "params": params,
            "body": body
        }
    # Fim função

    def visitCompoundStatement(self, ctx:MiniCParser.CompoundStatementContext):
        body = []
        if ctx.blockItemList():
            body = self.visit(ctx.blockItemList())
        return body

    def visitBlockItemList(self, ctx:MiniCParser.BlockItemListContext):
        items = []
        for item in ctx.blockItem():
            resultado_item = self.visit(item)
            if resultado_item:
                items.append(resultado_item)
        return items

    def visitBlockItem(self, ctx:MiniCParser.BlockItemContext):
        if ctx.statement(): return self.visit(ctx.statement())
        if ctx.declaration(): return self.visit(ctx.declaration())
        return None

    def visitDeclaration(self, ctx:MiniCParser.DeclarationContext):
        var_type = self.visit(ctx.typeSpecifier())
        if ctx.initDeclaratorList():
            init_decl = ctx.initDeclaratorList().initDeclarator(0)
            name = init_decl.declarator().getText()
            value = None
            is_array = False
            array_size = None
            
            if '[' in name and name.endswith(']'):
                is_array = True
                base = name.split('[')[0]
                size_part = name[name.find('[')+1:-1].strip()
                if size_part in self.defines: size_part = str(self.defines[size_part])
                name = base
                if size_part != '':
                    try: array_size = int(size_part)
                    except: array_size = None

            if init_decl.initializer():
                init = init_decl.initializer()
                if init.assignmentExpression():
                    value = self.visit(init.assignmentExpression())
                elif init.initializerList():
                    values = []
                    for it in init.initializerList().initializer():
                        if it.assignmentExpression(): values.append(self.visit(it.assignmentExpression()))
                        else: values.append(None)
                    # Normalize type for struct/union mapping
                    vt = var_type.replace(' ', '')
                    if vt.startswith('struct'):
                        # Extract name after 'struct' allowing both 'structX' and 'struct X'
                        tname = var_type.split(' ', 1)[-1] if ' ' in var_type else vt[len('struct'):]
                        fields = self.struct_defs.get(tname, [])
                        if fields:
                            mapped = {}
                            for i, fname in enumerate(fields):
                                if i < len(values): mapped[fname] = values[i]
                            value = mapped
                        else:
                            value = values
                    elif vt.startswith('union'):
                        tname = var_type.split(' ', 1)[-1] if ' ' in var_type else vt[len('union'):]
                        fields = self.union_defs.get(tname, [])
                        if fields and len(values) > 0:
                            mapped = {fields[0]: values[0], "_active": fields[0]}
                            value = mapped
                        else:
                            value = values
            return {"type": "Declaration", "varType": var_type, "name": name, "value": value, "isArray": is_array, "size": array_size}
        return None

    def visitTypeSpecifier(self, ctx:MiniCParser.TypeSpecifierContext):
        # Struct/union com campos
        if ctx.structOrUnionSpecifier():
            spec = ctx.structOrUnionSpecifier()
            su = spec.structOrUnion().getText()  # 'struct' or 'union'
            name = None
            fields = []
            if spec.Identifier():
                name = spec.Identifier().getText()
            if spec.structDeclarationList():
                sdl = spec.structDeclarationList()
                for sdecl in sdl.structDeclaration():
                    sdlst = sdecl.structDeclaratorList()
                    for sd in sdlst.structDeclarator():
                        d = sd.declarator()
                        dd = d.directDeclarator()
                        while dd.directDeclarator():
                            dd = dd.directDeclarator()
                        if dd.Identifier():
                            fields.append(dd.Identifier().getText())
            if name and fields:
                if su == 'struct':
                    self.struct_defs[name] = fields
                else:
                    self.union_defs[name] = fields
            if name:
                return f"{su} {name}"
            else:
                anon_name = f"__anon_{su}_{id(spec)}"
                if fields:
                    if su == 'struct': self.struct_defs[anon_name] = fields
                    else: self.union_defs[anon_name] = fields
                return f"{su} {anon_name}"
        return ctx.getText()

    def visitStatement(self, ctx:MiniCParser.StatementContext):
        if ctx.jumpStatement(): return self.visit(ctx.jumpStatement())
        elif ctx.selectionStatement(): return self.visit(ctx.selectionStatement())
        elif ctx.iterationStatement(): return self.visit(ctx.iterationStatement())
        elif ctx.expressionStatement(): return self.visit(ctx.expressionStatement())
        elif ctx.compoundStatement(): return {"type": "Block", "body": self.visit(ctx.compoundStatement())}
        return None

    def visitJumpStatement(self, ctx:MiniCParser.JumpStatementContext):
        if ctx.Return():
            value = None
            if ctx.expression(): value = self.visit(ctx.expression())
            return {"type": "Return", "value": value}
        return None

    def visitSelectionStatement(self, ctx:MiniCParser.SelectionStatementContext):
        if ctx.If():
            condition = self.visit(ctx.expression())
            then_stmt = self.visit(ctx.statement(0))
            if len(ctx.statement()) > 1:
                else_stmt = self.visit(ctx.statement(1))
                then_body = then_stmt["body"] if then_stmt and then_stmt.get("type") == "Block" else [then_stmt] if then_stmt else []
                else_body = else_stmt["body"] if else_stmt and else_stmt.get("type") == "Block" else [else_stmt] if else_stmt else []
                return {"type": "IfElse", "condition": condition, "thenBody": then_body, "elseBody": else_body}
            else:
                then_body = then_stmt["body"] if then_stmt and then_stmt.get("type") == "Block" else [then_stmt] if then_stmt else []
                return {"type": "If", "condition": condition, "thenBody": then_body}
        elif ctx.Switch():
            value = self.visit(ctx.expression())
            switch_body = ctx.statement(0)
            cases = []
            if switch_body.compoundStatement() and switch_body.compoundStatement().blockItemList():
                cases = self.processSwitchCases(switch_body.compoundStatement().blockItemList())
            return {"type": "Switch", "value": value, "cases": cases}
        return None
    
    def processSwitchCases(self, blockItemList):
        cases = []
        current_case = None
        for item in blockItemList.blockItem():
            if item.statement() and item.statement().labeledStatement():
                labeled = item.statement().labeledStatement()
                if current_case: cases.append(current_case)
                if labeled.Case():
                    case_value = self.visit(labeled.constantExpression())
                    current_case = {"type": "Case", "value": case_value, "body": [], "hasBreak": False}
                    case_stmt = self.visit(labeled.statement())
                    if case_stmt:
                        if case_stmt.get("type") == "Block": current_case["body"] = case_stmt["body"]
                        else: current_case["body"] = [case_stmt]
                elif labeled.Default():
                    current_case = {"type": "Default", "body": []}
                    default_stmt = self.visit(labeled.statement())
                    if default_stmt:
                        if default_stmt.get("type") == "Block": current_case["body"] = default_stmt["body"]
                        else: current_case["body"] = [default_stmt]
            else:
                if current_case:
                    stmt = None
                    if item.statement():
                        stmt = self.visit(item.statement())
                        if stmt and stmt.get("type") == "Break":
                            current_case["hasBreak"] = True
                            continue
                    elif item.declaration(): stmt = self.visit(item.declaration())
                    if stmt:
                        if stmt.get("type") == "Block": current_case["body"].extend(stmt["body"])
                        else: current_case["body"].append(stmt)
        if current_case: cases.append(current_case)
        return cases
    
    def visitIterationStatement(self, ctx:MiniCParser.IterationStatementContext):
        if ctx.While() and not ctx.Do():
            condition = self.visit(ctx.expression())
            body_stmt = self.visit(ctx.statement())
            body = body_stmt["body"] if body_stmt and body_stmt.get("type") == "Block" else [body_stmt] if body_stmt else []
            return {"type": "While", "condition": condition, "body": body}
        elif ctx.Do():
            body_stmt = self.visit(ctx.statement())
            body = body_stmt["body"] if body_stmt and body_stmt.get("type") == "Block" else [body_stmt] if body_stmt else []
            condition = self.visit(ctx.expression())
            return {"type": "DoWhile", "body": body, "condition": condition}
        elif ctx.For():
            for_cond = ctx.forCondition()
            init = None
            if for_cond.forDeclaration(): init = self.visit(for_cond.forDeclaration())
            elif for_cond.expression(0): init = self.visitExpressionAsStatement(for_cond.expression(0))
            condition = None
            if len(for_cond.expression()) > 1: condition = self.visit(for_cond.expression(1))
            elif len(for_cond.expression()) == 1 and not for_cond.forDeclaration(): condition = self.visit(for_cond.expression(0))
            increment = None
            if len(for_cond.expression()) >= 2: increment = self.visit(for_cond.expression(2))
            elif len(for_cond.expression()) == 2 and not for_cond.forDeclaration(): increment = self.visit(for_cond.expression(1))
            body_stmt = self.visit(ctx.statement())
            body = body_stmt["body"] if body_stmt and body_stmt.get("type") == "Block" else [body_stmt] if body_stmt else []
            return {"type": "For", "init": init, "condition": condition, "increment": increment, "body": body}
        return None
    
    def visitForDeclaration(self, ctx:MiniCParser.ForDeclarationContext):
        var_type = self.visit(ctx.typeSpecifier())
        init_decl = ctx.initDeclaratorList().initDeclarator(0)
        name = init_decl.declarator().getText()
        value = None
        is_array = False
        array_size = None
        if '[' in name and name.endswith(']'):
            is_array = True
            base = name.split('[')[0]
            size_part = name[name.find('[')+1:-1]
            if size_part in self.defines: size_part = str(self.defines[size_part])
            name = base
            if size_part.strip() != '':
                try: array_size = int(size_part)
                except: array_size = None
        if init_decl.initializer():
            init = init_decl.initializer()
            if init.assignmentExpression(): value = self.visit(init.assignmentExpression())
            elif init.initializerList():
                values = []
                for it in init.initializerList().initializer():
                    if it.assignmentExpression(): values.append(self.visit(it.assignmentExpression()))
                    else: values.append(None)
                value = values
        return {"type": "Declaration", "varType": var_type, "name": name, "value": value, "isArray": is_array, "size": array_size}
    
    def visitExpressionStatement(self, ctx:MiniCParser.ExpressionStatementContext):
        if ctx.expression(): return self.visitExpressionAsStatement(ctx.expression())
        return None
    
    def visitExpressionAsStatement(self, expr_ctx):
        if expr_ctx.assignmentExpression():
            assign_expr = expr_ctx.assignmentExpression(0)
            if assign_expr.assignmentOperator():
                var_name = self.visit(assign_expr.unaryExpression()) 
                value = self.visit(assign_expr.assignmentExpression())
                return {"type": "Assignment", "name": var_name, "value": value}
            else: return self.visit(assign_expr)
        return None
    
    def visitConstantExpression(self, ctx:MiniCParser.ConstantExpressionContext):
        res = self.visit(ctx.conditionalExpression())
        if isinstance(res, str) and res in self.defines:
            return self.defines[res]
        return res
        
    def visitExpression(self, ctx:MiniCParser.ExpressionContext):
        return self.visit(ctx.assignmentExpression(0))
    def visitAssignmentExpression(self, ctx:MiniCParser.AssignmentExpressionContext):
        if ctx.assignmentOperator():
            var_name = self.visit(ctx.unaryExpression())
            value = self.visit(ctx.assignmentExpression())
            return {"type": "Assignment", "name": var_name, "value": value}
        return self.visit(ctx.conditionalExpression())
    def visitConditionalExpression(self, ctx:MiniCParser.ConditionalExpressionContext):
        return self.visit(ctx.logicalOrExpression())
    def visitLogicalOrExpression(self, ctx:MiniCParser.LogicalOrExpressionContext):
        if ctx.getChildCount() == 3: return {"type": "BinaryOp", "op": "||", "left": self.visit(ctx.getChild(0)), "right": self.visit(ctx.getChild(2))}
        return self.visit(ctx.logicalAndExpression(0))
    def visitLogicalAndExpression(self, ctx:MiniCParser.LogicalAndExpressionContext):
        if ctx.getChildCount() == 3: return {"type": "BinaryOp", "op": "&&", "left": self.visit(ctx.getChild(0)), "right": self.visit(ctx.getChild(2))}
        return self.visit(ctx.inclusiveOrExpression(0))
    def visitExclusiveOrExpression(self, ctx:MiniCParser.ExclusiveOrExpressionContext): return self.visit(ctx.andExpression(0))
    def visitAndExpression(self, ctx:MiniCParser.AndExpressionContext): return self.visit(ctx.equalityExpression(0))
    def visitEqualityExpression(self, ctx:MiniCParser.EqualityExpressionContext):
        if ctx.getChildCount() == 3: return {"type": "BinaryOp", "op": ctx.getChild(1).getText(), "left": self.visit(ctx.getChild(0)), "right": self.visit(ctx.getChild(2))}
        return self.visit(ctx.relationalExpression(0))
    def visitRelationalExpression(self, ctx:MiniCParser.RelationalExpressionContext):
        if ctx.getChildCount() == 3: return {"type": "BinaryOp", "op": ctx.getChild(1).getText(), "left": self.visit(ctx.getChild(0)), "right": self.visit(ctx.getChild(2))}
        return self.visit(ctx.additiveExpression(0))
    def visitAdditiveExpression(self, ctx:MiniCParser.AdditiveExpressionContext):
        result = self.visit(ctx.multiplicativeExpression(0))
        mult_count = len(ctx.multiplicativeExpression())
        for i in range(1, mult_count):
            op_index = i * 2 - 1
            op = ctx.getChild(op_index).getText()
            right = self.visit(ctx.multiplicativeExpression(i))
            result = {"type": "BinaryOp", "op": op, "left": result, "right": right}
        return result
    def visitMultiplicativeExpression(self, ctx:MiniCParser.MultiplicativeExpressionContext):
        result = self.visit(ctx.castExpression(0))
        cast_count = len(ctx.castExpression())
        for i in range(1, cast_count):
            op_index = i * 2 - 1
            op = ctx.getChild(op_index).getText()
            right = self.visit(ctx.castExpression(i))
            result = {"type": "BinaryOp", "op": op, "left": result, "right": right}
        return result
    def visitCastExpression(self, ctx:MiniCParser.CastExpressionContext): return self.visit(ctx.unaryExpression())
    
    # Unary expression
    def visitUnaryExpression(self, ctx:MiniCParser.UnaryExpressionContext):
        if ctx.unaryOperator():
            op = ctx.unaryOperator().getText()
            expr = self.visit(ctx.castExpression())
            return {"type": "UnaryOp", "op": op, "expr": expr}
        return self.visit(ctx.postfixExpression())
    
    def visitPostfixExpression(self, ctx:MiniCParser.PostfixExpressionContext):
        node = self.visit(ctx.primaryExpression())
        i = 1
        child_count = ctx.getChildCount()
        while i < child_count:
            child = ctx.getChild(i)
            txt = child.getText()
            if txt == '[':
                index_ctx = ctx.getChild(i+1)
                index_node = self.visit(index_ctx)
                node = {"type": "ArrayAccess", "array": node, "index": index_node}
                i += 3
                continue
            elif txt == '(':
                func_name = node 
                args = []
                possible_args = ctx.getChild(i+1)
                if possible_args.getText() != ')':
                    arg_list_ctx = possible_args 
                    for expr in arg_list_ctx.assignmentExpression(): args.append(self.visit(expr))
                    i += 3
                else: i += 2
                node = {"type": "Call", "callee": func_name, "args": args}
                continue
            elif txt == '.' or txt == '->':
                # Acesso de campo
                field_ident = ctx.getChild(i+1).getText()
                node = {"type": "FieldAccess", "object": node, "field": field_ident}
                i += 2
                continue
            i += 1
        return node
    
    def visitPrimaryExpression(self, ctx:MiniCParser.PrimaryExpressionContext):
        if ctx.Identifier():
            nome = ctx.Identifier().getText()
            if nome in self.defines:
                val = self.defines[nome]
                if isinstance(val, str) and val.startswith('"') and val.endswith('"'):
                    return {"type": "String", "value": val[1:-1]}
                return val
            return nome
        if ctx.Constant():
            txt = ctx.Constant().getText()
            if txt.startswith("'") and txt.endswith("'"):
                inner = txt[1:-1]
                if inner.startswith('\\') and len(inner) >= 2: val = inner[1]
                else: val = inner
                return {"type": "Char", "value": val}
            if '.' in txt: return float(txt)
            try: return int(txt)
            except: return int(txt)
        if ctx.StringLiteral():
            parts = []
            for i in range(len(ctx.StringLiteral())):
                s = ctx.StringLiteral(i).getText()
                inner = s[1:-1]
                inner = inner.replace('\\"', '"').replace('\\\\', '\\')
                parts.append(inner)
            full = ''.join(parts)
            return {"type": "String", "value": full}
        if ctx.LeftParen():
            return self.visit(ctx.expression())
        return None

def main(argv):
    input_path = argv[1]
    output_path = "codigo_simplificado.json"
    input_stream = FileStream(input_path, encoding='utf-8')
    lexer = MiniCLexer(input_stream)
    stream = CommonTokenStream(lexer)
    parser = MiniCParser(stream)
    tree = parser.compilationUnit()
    visitor = AstVisitor()
    ast_simplificada = visitor.visit(tree)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(ast_simplificada, f, indent=2)
    print(f"✅ AST simplificada gerada em {output_path}")

if __name__ == '__main__':
    main(sys.argv)