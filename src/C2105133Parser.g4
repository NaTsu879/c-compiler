parser grammar C2105133Parser;

options {
	tokenVocab = C2105133Lexer;
}

@parser::header {
    #include <iostream>
    #include <fstream>
    #include <string>
    #include <cstdlib>
    #include <functional>
    #include <sstream>
    #include <vector>
    #include <regex>
    #include <unordered_map>
    #include <unordered_set>
    #include <stack>
    #include "C2105133Lexer.h"
    #include "2105133_SymbolTable.h"

    using namespace std;

    extern ofstream parserLogFile;
    extern ofstream errorFile;
    extern ofstream asmFile;
    extern ifstream libFile;
    extern SymbolTable Table;
    extern int syntaxErrorCount;
    extern int offset;
    extern int labelcount;
    extern int retcount;
    extern stack<string> elselabels;
    extern stack<string> exitlabels;
    extern stack<string> looplabels;
    extern stack<string> inclabels;
    extern stack<string> backlabels;
    extern stack<string> returnlabels;
}

@parser::members {
    void writeIntoparserLogFile(const string message) {
        if (!parserLogFile) {
            cout << "Error opening parserLogFile.txt" << endl;
            return;
        }

        parserLogFile << message << endl;
        parserLogFile.flush();
    }

    void writeIntoasmFile(const string message) {
        asmFile.flush();
        string filename = "output/asmFile.asm";
        asmFile.close();
        vector<string> lines;
        
        ifstream readfile;
        readfile.open(filename);
        string line;
        while (getline(readfile, line)) {
            lines.push_back(line);
        }
        readfile.close();


        
        ofstream file;
        file.open(filename, ios::out | ios::trunc); // clear and write
        for (const string& l : lines) {
            if(l == ".CODE")
                file << message << '\n';
            file << l << '\n';
        }
        file.close();

        lines.clear();
        asmFile.open(filename, ios::app);
    }

    void writeIntoErrorFile(const string message) {
        if (!errorFile) {
            cout << "Error opening errorFile.txt" << endl;
            return;
        }
        syntaxErrorCount++;
        errorFile << message << endl;
        errorFile.flush();
    }

    string newlabel()
    {
        labelcount++;
        return "L" + to_string(labelcount);
    }

    string trim(const string& str) 
    {
        size_t start = str.find_first_not_of(" \t\r\n");
        size_t end = str.find_last_not_of(" \t\r\n");
        return (start == string::npos) ? "" : str.substr(start, end-start+1);
    }

    
    vector<string> optimizeAssembly(const vector<string>& lines) {
        vector<string> temp;
        int i = 0;

        while (i < lines.size()) {
            string fullLine = lines[i];
            string fullNext = (i + 1 <lines.size()) ? lines[i + 1] : "";

            
            string line = trim(fullLine.substr(0, fullLine.find(';')));
            string next = trim(fullNext.substr(0, fullNext.find(';')));

            smatch match1, match2;

            
            if (regex_match(line, match1, regex(R"(MOV\s+(\w+),\s*(\w+))", regex::icase)) &&
                regex_match(next, match2, regex(R"(MOV\s+(\w+),\s*(\w+))", regex::icase))) {
                if (match1[1] == match2[2] && match1[2] == match2[1]) {
                    temp.push_back(fullLine);  
                    i += 2;
                    continue;
                }
            }

            
            if (regex_match(line, match1, regex(R"(PUSH\s+(\w+))", regex::icase)) &&
                regex_match(next, match2, regex(R"(POP\s+(\w+))", regex::icase))) {
                if (match1[1] == match2[1]) {
                    i += 2; 
                    continue;
                }
            }

            
            if (regex_match(line, regex(R"((ADD|SUB)\s+\w+,\s*0)", regex::icase)) ||
                regex_match(line, regex(R"(MUL\s+\w+,\s*1)", regex::icase)) ||
                regex_match(line, regex(R"(IMUL\s+\w+,\s*1)", regex::icase)) ||
                regex_match(line, regex(R"(AND\s+\w+,\s*0?FFFFh)", regex::icase))) {
                i++;
                continue;
            }

            if (regex_match(line, match1, regex(R"(JMP\s+(\w+))", regex::icase)) &&
                regex_match(next, match2, regex(R"((\w+):)", regex::icase))) {
                if (match1[1] == match2[1]) {
                    i+= 1;
                    continue;
                }
            }

            temp.push_back(fullLine);
            i++;
        }

      
        vector<string> result;
        unordered_map<string, string> labelMap;
        vector<string> labelBuffer;

        for (const string& raw : temp) {
            string line = trim(raw.substr(0, raw.find(';')));
            smatch match;
            if (regex_match(line, match, regex(R"((\w+):)", regex::icase))) {
                labelBuffer.push_back(match[1]);
            } else {
                if (!labelBuffer.empty()) {
                    string finalLabel = labelBuffer.back();
                    result.push_back(finalLabel + ":");
                    for (size_t j = 0; j + 1 < labelBuffer.size(); ++j) {
                        labelMap[labelBuffer[j]] = finalLabel;
                    }
                    labelBuffer.clear();
                }
                result.push_back(raw);
            }
        }

        
        if (!labelBuffer.empty()) {
            string finalLabel = labelBuffer.back();
            result.push_back(finalLabel + ":");
            for (size_t j = 0; j + 1 < labelBuffer.size(); ++j) {
                labelMap[labelBuffer[j]] = finalLabel;
            }
        }

        
        vector<string> final;
        regex jumpRegex(R"(\b(JMP|JE|JNE|JG|JL|JGE|JLE|JNZ|JZ)\s+(\w+))", regex::icase);

        for (string line : result) {
            smatch match;
            if (regex_search(line, match, jumpRegex)) {
                string oldLabel = match[2];
                string resolved = oldLabel;
                while (labelMap.count(resolved)) {
                    resolved = labelMap[resolved];
                }
                line = regex_replace(line, regex(R"(\b)" + oldLabel + R"(\b)"), resolved);
            }
            final.push_back(line);
        }

        return final;
    }

    void optcodegen()
    {
        asmFile.flush();
        string filename = "output/asmFile.asm";
        string optfilename = "output/optasmFile.asm";
        asmFile.close();

        vector<string> lines;
        
        {
            ifstream readfile(filename);
            string line;
            while (getline(readfile, line)) {
                lines.push_back(line);
            }
        }

        vector <string> result =  optimizeAssembly(lines);

        {
            ofstream file(optfilename, ios::out | ios::trunc); 
            for (const string& l : result) {
                file << l << '\n';
            }
        }

        result.clear();
        lines.clear();
        asmFile.open(filename, ios::app);
    }

    vector<string> extractParamTypes(const string& paramListText, bool definition, bool insert=false, int line = 0 ) {
        vector<string> paramTypes;
        
        istringstream ss(paramListText);
        string param;

        while (getline(ss, param, ',')) {
            istringstream wordStream(param);
            string type;
            wordStream >> type; 
            if (!type.empty()) {
                paramTypes.push_back(type);
                if(definition)
                {
                    string name;
                    wordStream >> name;
                    if(insert)
                    {
                        bool success = Table.insert(name, type);
                        if(!success)
                        {
                            writeIntoErrorFile("Error at line " + to_string(line) + ": Multiple declaration of " + name + " in parameter\n");
                            writeIntoparserLogFile("Error at line " + to_string(line) + ": Multiple declaration of " + name + " in parameter\n");
                        }else
                        {
                            SymbolInfo* item = Table.getCurrentScopeTable()->lookup(name);
                            item->setarray(false);
                            item->setGlobal(false);
                            item->setOffset(retcount);
                            retcount+=2;
                        }
                    }
                        
                }
            }
        }
        if(!insert)
        {
            retcount = -2 + paramTypes.size()*-2;
        }
        return paramTypes;
    }

    void insertFunctionDeclaration( string funcName, string returnType, string paramListText="", bool definition = false) {

        bool success = Table.insert(funcName, "ID");

        if (!success) {
            cerr << "Semantic Error: Function '" << funcName << "' already declared in current scope." << endl;
            return;
        }

        
        SymbolInfo* funcSymbol = Table.lookup(funcName);
        if (!funcSymbol) {
            cerr << "Internal Error: Inserted function not found during lookup." << endl;
            return;
        }

        
        //Table.enterScope();
        
        
        vector<string> paramTypes = extractParamTypes(paramListText, definition);

        
        funcSymbol->setIsFunction(true);
        funcSymbol->setReturnType(returnType);
        funcSymbol->setParamTypes(paramTypes); 
        if(!definition)
            funcSymbol->setIsDeclared(true);
        else
            funcSymbol->setIsDefined(true);
    }


    void insertVarDeclarations(string &type, const string &declListText, string line) {
        stringstream ss(declListText);
        string name;
        
        while (getline(ss, name, ',')) {
            
            int bracketPos = name.find('[');
            int bracketEnd = name.find(']');
            string num;
            string temp = type;
            if (bracketPos != string::npos) {
                num = name.substr(bracketPos+1,bracketEnd-2);
                name = name.substr(0, bracketPos);
                type += " array";
            }

            bool success = Table.insert(name, type);
            
            SymbolInfo* item = Table.lookup(name);
            if(item){
                if (Table.getCurrentScopeTable()->getID() == "1")
                {
                    item->setGlobal(true);
                    if(bracketPos != string::npos)
                    {
                        item->setarray(true);
                        item->setarraylen(stoi(num));
                        writeIntoasmFile ( name + " DW " + num + " DUP (0)" );
                    }else
                    {
                        writeIntoasmFile(name + " DW 0");
                    }
                }else if(bracketPos != string::npos)
                {
                   int len = 2*stoi(num);
                   asmFile<< "\tSUB SP ,"<<len<<"\t\t\t; Line "<< line<< endl;
                   item->setarray(true);
                   item->setarraylen(len/2);
                   item->setGlobal(false);
                   item->setOffset(offset+2);
                   offset += len ;
                }
                else
                {
                    asmFile<< "\tPUSH 0"<<"\t\t\t; Line "<< line<< endl;
                    item->setarray(false);
                    item->setGlobal(false);
                    item->setOffset(offset);
                    offset += 2;
                } 
            }    
            type = temp;
            if (!success) {
               // writeIntoErrorFile("Error at line " + line + ": Multiple declaration of " + name);
            }
        }
    }

}

start
    : {
        asmFile << ".MODEL SMALL" << endl;
        asmFile << ".STACK 100h" << endl;
        asmFile << ".DATA" << endl;
        asmFile << "number DB \"00000$\" "<<endl;
        asmFile << ".CODE" <<endl;
      }
      p=program
      {
        writeIntoparserLogFile(
            "Line " + to_string($p.stop->getLine()) +
            ": start : program \n\n" + "\n"
        );
        Table.printAllScopeTable(parserLogFile);
        writeIntoparserLogFile("Total lines: " + to_string($p.stop->getLine()) +
        "\nTotal errors: " + to_string(syntaxErrorCount) + "\n");

        string line;
        while (getline(libFile, line)) {
            asmFile << line << endl;
        }

        asmFile << "END main"<<endl;
        optcodegen();
      }
    ;


program
	returns[string act_text]:
	p = program u = unit {
        $act_text = $p.act_text + $u.act_text;
        writeIntoparserLogFile(
            "Line " + to_string($u.stop->getLine()) +
            ": program : program unit\n\n" + $act_text + "\n"
        );
    }
	| u = unit {
        $act_text = $u.act_text;
        writeIntoparserLogFile(
            "Line " + to_string($u.stop->getLine()) +
            ": program : unit\n\n" + $act_text + "\n"
        );
    };

unit
	returns[string act_text]:
	vd = var_declaration {
        $act_text = $vd.act_text;
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": unit : var_declaration\n\n" + $act_text + "\n"
        );
    }
	| fd = func_declaration {
        $act_text = $fd.act_text;
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": unit : func_declaration\n\n" + $act_text + "\n"
        );
    }
	| f = func_definition {
        $act_text = $f.act_text + "\n";
        writeIntoparserLogFile(
            "Line " + to_string($f.stop->getLine()) +
            ": unit : func_definition\n\n" + $act_text + "\n"
        );
    };

func_declaration
	returns[string act_text]:
	t = type_specifier ID LPAREN p = parameter_list RPAREN SEMICOLON {
        $act_text = $t.act_text + " " + $ID->getText() + "(" + $p.act_text + ")" + ";\n";
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON\n\n" +
            $act_text + "\n"
        );
        insertFunctionDeclaration($ID->getText(),$t.act_text,$p.act_text);
        Table.enterScope();
        vector <string> store = extractParamTypes($p.act_text, true, true, $ctx->getStart()->getLine());
        Table.exitScope();
    }
	| t = type_specifier ID LPAREN RPAREN SEMICOLON {
         $act_text = $t.act_text + " " + $ID->getText() + "(" + ")" + ";\n";
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": func_declaration : type_specifier ID LPAREN RPAREN SEMICOLON\n\n" +
            $act_text + "\n"
        );
        insertFunctionDeclaration($ID->getText(),$t.act_text);
        Table.enterScope();
        Table.exitScope();
    };

func_definition
	returns[string act_text, int Line]:
	t = type_specifier ID LPAREN p = parameter_list RPAREN {
    SymbolInfo* temp = Table.lookup($ID->getText());
        if(temp!=nullptr){
            if(!temp->getIsDeclared())
            {
                //insertFunctionDeclaration($ID->getText(),$t.act_text,$p.act_text,true);
                writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
                writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n"); 
            }
            else{
                if($t.act_text != temp->getReturnType())
                {
                    writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Return type mismatch with function declaration in function " + $ID->getText() + "\n");
                    writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Return type mismatch with function declaration in function " + $ID->getText() + "\n");   
                }
                vector <string> param = extractParamTypes($p.act_text, false);
                if(param.size() != temp->getParamTypes().size())
                {
                    writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Total number of arguments mismatch with declaration in function " + $ID->getText() + "\n");
                    writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Total number of arguments mismatch with declaration in function " + $ID->getText() + "\n"); 
                }
            }
            Table.enterScope();
            vector <string> store = extractParamTypes($p.act_text, true, true, $ctx->getStart()->getLine());
        }else
        {
            
            insertFunctionDeclaration($ID->getText(),$t.act_text,$p.act_text,true);
            Table.enterScope();
            vector <string> store = extractParamTypes($p.act_text, true, true, $ctx->getStart()->getLine());
        }

        asmFile <<$ID->getText()<< " PROC" <<"\t\t\t; Line "<< to_string($ID->getLine())<<endl;
        asmFile << "\tPUSH BP"<<endl;
        asmFile <<  "\tMOV BP, SP"<<endl;
    }
    c = compound_statement[false] {
        $act_text = $t.act_text + " " + $ID->getText() + "(" + $p.act_text + ")" + $c.act_text;
        $Line = $c.Line;
        writeIntoparserLogFile(
            "Line " + to_string($c.stop->getLine()) +
            ": func_definition : type_specifier ID LPAREN parameter_list RPAREN compound_statement\n\n" +
            $act_text + "\n"
        );
        Table.exitScope();
        SymbolInfo *item = Table.getCurrentScopeTable()->lookup($ID->getText());
        vector <string > store;
        if(item)
        {
            store = item->getParamTypes();
        }
        if(!returnlabels.empty())
        {   
            asmFile<<returnlabels.top()<<":"<<endl;
            returnlabels.pop();
        }
        asmFile<< "\tADD SP, "<<offset-2<<endl;
        offset = 2;
        asmFile <<"\tPOP BP"<<endl;
        asmFile <<"\tRET "<<store.size()*2<<endl;
        asmFile << $ID->getText() << " ENDP" << endl;
    }
	| t = type_specifier ID LPAREN RPAREN
    {
        SymbolInfo* temp = Table.lookup($ID->getText());
        if(temp!=nullptr){
            if(!temp->getIsDeclared())
                 insertFunctionDeclaration($ID->getText(),$t.act_text,"",true);
            Table.enterScope();
        }else
        {
            if($ID->getText()=="main")
            {    
               
                asmFile << "main PROC" <<"\t\t\t; Line "<< to_string($ID->getLine())<<endl;
                asmFile << "\tMOV AX, @DATA"<<endl;
                asmFile << "\tMOV DS, AX"<<endl;
                asmFile << "\tPUSH BP"<<endl;
                asmFile <<  "\tMOV BP, SP"<<endl;
            }else
            {
                asmFile <<$ID->getText()<< " PROC"<<"\t\t\t; Line "<< to_string($ID->getLine()) <<endl;
                asmFile << "\tPUSH BP"<<endl;
                asmFile <<  "\tMOV BP, SP"<<endl;
            }
            insertFunctionDeclaration($ID->getText(),$t.act_text,"",true);
            Table.enterScope();
        }
    } c = compound_statement[false] {
        $act_text =  $t.act_text + " " + $ID->getText() + "(" + ")" + $c.act_text;
        $Line = $c.Line;
        writeIntoparserLogFile(
            "Line " + to_string($c.stop->getLine()) +
            ": func_definition : type_specifier ID LPAREN RPAREN compound_statement\n\n" +
            $act_text + "\n"
        );
        Table.exitScope();

        if($ID->getText()=="main")
        {    
               
                if(!returnlabels.empty())
                {   
                    asmFile<<returnlabels.top()<<":"<<endl;
                    returnlabels.pop();
                }
                asmFile<< "\tADD SP, "<<offset-2<<endl;
	            asmFile <<"\tPOP BP"<<endl;
                asmFile << "\tMOV AX, 4C00H" << endl;
                asmFile << "\tINT 21H" << endl;
                asmFile << "MAIN ENDP" << endl;
        }else
        {
                if(!returnlabels.empty())
                {   
                    asmFile<<returnlabels.top()<<":"<<endl;
                    returnlabels.pop();
                }
                asmFile<< "\tADD SP, "<<offset-2<<endl;
	            asmFile <<"\tPOP BP"<<endl;
                asmFile <<"\tRET"<<endl;
                asmFile << $ID->getText() << " ENDP" << endl;
        }
        offset = 2;
        
    }
    | t = type_specifier ID LPAREN pe = parameter_list_err RPAREN {
        // This block handles error in parameter list
        writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Syntax error in parameter list of function " + $ID->getText() + "\n");
        writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Syntax error in parameter list of function " + $ID->getText() + "\n");
        Table.enterScope();  // still enter scope to allow compound_statement parsing
    } c = compound_statement[false] {
        $act_text = $t.act_text + " " + $ID->getText() + "(" + $pe.act_text + ")" + $c.act_text;
        $Line = $c.Line;
        writeIntoparserLogFile("Line " + to_string($c.stop->getLine()) + ": func_definition : type_specifier ID LPAREN parameter_list_err RPAREN compound_statement\n\n" + $act_text + "\n");
        Table.exitScope();
    }
    ; 

parameter_list_err returns [string act_text] : (.)+? {
    $act_text = $ctx->getText();
}
;
parameter_list
	returns[string act_text]:
	p = parameter_list COMMA t = type_specifier ID {
        $act_text = $p.act_text + "," + $t.act_text + " " + $ID->getText();
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": parameter_list : parameter_list COMMA type_specifier ID\n\n" +
            $act_text + "\n"
        );
    }
	| p = parameter_list COMMA t = type_specifier {
        $act_text = $p.act_text + "," + $t.act_text;
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": parameter_list : parameter_list COMMA type_specifier\n\n" +
            $act_text + "\n"
        );
    }
	| t = type_specifier ID {
        $act_text = $t.act_text + " " + $ID->getText();
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": parameter_list : type_specifier ID\n\n" +
            $act_text + "\n"
        );
    }
	| t = type_specifier {
        $act_text = $t.act_text ;
        writeIntoparserLogFile(
            "Line " + to_string($ctx->getStart()->getLine()) +
            ": parameter_list : type_specifier\n\n" +
            $act_text + "\n"
        );
    };


compound_statement [bool flagScope]
	returns[string act_text, int Line]:
	LCURL {if (flagScope) Table.enterScope();}
    s = statements RCURL {
        $act_text = "{\n" + $s.act_text + "}\n" ;
        $Line = $RCURL->getLine();
        writeIntoparserLogFile(
            "Line " + to_string($RCURL->getLine()) +
            ": compound_statement : LCURL statements RCURL\n\n" +
            $act_text + "\n\n\n"
        );
        Table.printAllScopeTable(parserLogFile);
        if (flagScope) Table.exitScope();
    }
	| LCURL {if (flagScope) Table.enterScope();}
     RCURL {
        $act_text = $ctx->getText();
        $Line = $RCURL->getLine();
        writeIntoparserLogFile(
            "Line " + to_string($RCURL->getLine()) +
            ": compound_statement : LCURL RCURL\n\n" +
            $act_text + "\n\n\n"
        );
        Table.printAllScopeTable(parserLogFile);
        if (flagScope) Table.exitScope();
    };

var_declaration
	returns[string act_text,int line ]:
	t = type_specifier dl = declaration_list sm = SEMICOLON {
        $act_text = $t.act_text + " " + $dl.act_text + ";\n" ;
        $line = $sm->getLine();
        writeIntoparserLogFile("Line " + to_string($sm->getLine()) + ": var_declaration : type_specifier declaration_list SEMICOLON \n");
        if($t.act_text == "void")
        {
            writeIntoErrorFile("Error at line " + to_string($sm->getLine()) + ": Variable type cannot be void " + "\n");
            writeIntoparserLogFile("Error at line " + to_string($sm->getLine()) + ": Variable type cannot be void " + "\n"); 
            
        }else
            insertVarDeclarations($t.act_text, $dl.act_text,to_string($sm->getLine()));
        writeIntoparserLogFile($act_text);
      }
	| t = type_specifier de = declaration_list_err sm = SEMICOLON {
        writeIntoErrorFile(
            string("Line# ") + to_string($sm->getLine()) +
            " with error name: " + $de.error_name +
            " - Syntax error at declaration list of variable declaration"
        );

        syntaxErrorCount++;
      };

declaration_list_err
	returns[string error_name]: 
	{
        $error_name = "Error in declaration list";
    };

type_specifier
	returns[string act_text]:
	INT {
            $act_text = $ctx->getText();
            writeIntoparserLogFile("Line " + to_string($INT->getLine()) + ": type_specifier : INT \n\nint \n");
        }
	| FLOAT {
            $act_text = $ctx->getText();
             writeIntoparserLogFile("Line " + to_string($FLOAT->getLine()) + ": type_specifier : FLOAT \n\nfloat \n");
        }
	| VOID {
            $act_text = $ctx->getText();
            writeIntoparserLogFile("Line " + to_string($VOID->getLine()) + ": type_specifier : VOID \n\nvoid \n");
        };

declaration_list
	returns[string act_text]:
	dl=declaration_list COMMA ID { 
        $act_text = $dl.act_text + "," + $ID->getText()  ;
        if(Table.getCurrentScopeTable()->lookup($ID->getText()))
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile("Line " + to_string($ID->getLine()) + ": declaration_list : declaration_list COMMA ID \n\n" + $act_text + "\n");
	}
	| dl=declaration_list COMMA ID LTHIRD CONST_INT RTHIRD { 
        $act_text = $dl.act_text + "," + $ID->getText() + "[" + $CONST_INT->getText() + "]" ;
        if(Table.getCurrentScopeTable()->lookup($ID->getText()))
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
        } 
        writeIntoparserLogFile("Line " + to_string($ID->getLine()) + ": declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD \n\n" + $act_text + "\n");
	}
	| ID { 
        $act_text = $ctx->getText(); 
        if(Table.getCurrentScopeTable()->lookup($ID->getText()))
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile("Line " + to_string($ID->getLine()) + ": declaration_list : ID \n\n" + $ctx->getText() + "\n");
	}
	| ID LTHIRD CONST_INT RTHIRD { 
        $act_text = $ctx->getText();
        if(Table.getCurrentScopeTable()->lookup($ID->getText()))
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Multiple declaration of " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile("Line " + to_string($ID->getLine()) + ": declaration_list : ID LTHIRD CONST_INT RTHIRD \n\n" + $ctx->getText() + "\n");
	}
    | dl=declaration_list ADDOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($ADDOP->getLine()) + ": syntax error, unexpected ADDOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($ADDOP->getLine()) + ": syntax error, unexpected ADDOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list ID {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": syntax error, unexpected ID, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": syntax error, unexpected ID, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list SUBOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($SUBOP->getLine()) + ": syntax error, unexpected SUBOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($SUBOP->getLine()) + ": syntax error, unexpected SUBOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list MULOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($MULOP->getLine()) + ": syntax error, unexpected MULOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($MULOP->getLine()) + ": syntax error, unexpected MULOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list INCOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($INCOP->getLine()) + ": syntax error, unexpected INCOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($INCOP->getLine()) + ": syntax error, unexpected INCOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list DECOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($DECOP->getLine()) + ": syntax error, unexpected DECOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($DECOP->getLine()) + ": syntax error, unexpected DECOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list NOT {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($NOT->getLine()) + ": syntax error, unexpected NOT, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($NOT->getLine()) + ": syntax error, unexpected NOT, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list RELOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($RELOP->getLine()) + ": syntax error, unexpected RELOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($RELOP->getLine()) + ": syntax error, unexpected RELOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list LOGICOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($LOGICOP->getLine()) + ": syntax error, unexpected LOGICOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($LOGICOP->getLine()) + ": syntax error, unexpected LOGICOP, expecting COMMA or SEMICOLON");
      }
    | dl=declaration_list ASSIGNOP {$act_text = $dl.act_text;
        writeIntoErrorFile("Error at line " + to_string($ASSIGNOP->getLine()) + ": syntax error, unexpected ASSIGNOP, expecting COMMA or SEMICOLON");
        writeIntoparserLogFile("Error at line " + to_string($ASSIGNOP->getLine()) + ": syntax error, unexpected ASSIGNOP, expecting COMMA or SEMICOLON");
      }

    ;

statements
	returns[string act_text]:
	s = statement {
        $act_text = $s.act_text;
        writeIntoparserLogFile("Line " + to_string($s.stop->getLine()) + ": statements : statement\n\n" + $act_text + "\n");
    }
	| ss = statements s = statement {
        $act_text = $ss.act_text + $s.act_text;
        writeIntoparserLogFile("Line " + to_string($s.stop->getLine()) + ": statements : statements statement\n\n" + $act_text + "\n");
    };

statement
	returns[string act_text, int line]:
	vd = var_declaration {
        $act_text = $vd.act_text;
        $line = $vd.line;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": statement : var_declaration\n\n" + $act_text + "\n");
    }
	| es = expression_statement {
        $act_text = $es.act_text +"\n";
        $line = $es.line;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": statement : expression_statement\n\n" + $act_text + "\n");
    }
	| cs = compound_statement[true] {
        $act_text = $cs.act_text;
        writeIntoparserLogFile("Line " + to_string($cs.stop->getLine()) + ": statement : compound_statement\n\n" + $act_text + "\n");
    }
	| FOR LPAREN es1 = expression_statement
    {
        string looplabel = newlabel();
        looplabels.push(looplabel);
        asmFile <<looplabel<<":" <<"\t\t\t; Line "<< to_string($FOR->getLine())<<endl;
    } es2 = expression_statement
    { 
        string inclabel = newlabel();
        string backlabel = newlabel();
        string exitlabel = newlabel();
        inclabels.push(inclabel);
        exitlabels.push(exitlabel);
        backlabels.push(backlabel);
        asmFile << "\tCMP AX, 1" <<"\t\t\t; Line "<< to_string($FOR->getLine())<<endl;
        asmFile << "\tJE "<<inclabel<<endl;
        asmFile << "\tJMP "<<exitlabel<<endl;
        asmFile << backlabel << ":" <<endl;
        //backlabel;
        
    } e1 = expression
    {
        asmFile <<"\tPOP AX"<<"\t\t\t; Line "<< to_string($FOR->getLine())<<endl;
        asmFile << "\tJMP "<<looplabels.top() <<endl;//looplabel
        looplabels.pop();
        asmFile << inclabels.top() <<":"<<endl;
        inclabels.pop();
        //inclabel

    }RPAREN s1 = statement {
        $act_text = "for(" + $es1.act_text + $es2.act_text + $e1.act_text + ")" + $s1.act_text ;
        writeIntoparserLogFile("Line " + to_string($s1.stop->getLine()) + ": statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement\n\n" + $act_text + "\n");
        asmFile << "\tJMP "<<backlabels.top() <<endl;
        //jmp backlabel
        backlabels.pop();
        asmFile <<exitlabels.top()<<":"<<endl;
        exitlabels.pop();

    }
	| IF LPAREN e = expression
    {
        string elselabel = newlabel();
        elselabels.push(elselabel);
        asmFile<< "\tPOP AX"<<"\t\t\t; Line "<< to_string($IF->getLine())<<endl;
        asmFile<< "\tCMP AX, 0"<<endl;
        asmFile<< "\tJE "<<elselabel<<endl;

    } RPAREN s = statement {
        $act_text = "if (" + $e.act_text + ")" + $s.act_text ;
        writeIntoparserLogFile("Line " + to_string($s.stop->getLine()) + ": statement : IF LPAREN expression RPAREN statement\n\n" + $act_text + "\n");
    
        asmFile<< elselabels.top()<< ":" <<endl;
        elselabels.pop();
    }
	|IF LPAREN e = expression
    {
        string elselabel = newlabel();
        elselabels.push(elselabel);
        asmFile<< "\tPOP AX"<<"\t\t\t; Line "<< to_string($IF->getLine())<<endl;
        asmFile<< "\tCMP AX, 0"<<endl;
        asmFile<< "\tJE "<<elselabel<<endl; 

    }RPAREN s = statement
    {
        string exitlabel = newlabel();
        exitlabels.push(exitlabel);
        asmFile<< "\tJMP "<<exitlabel<<endl;
        asmFile<< elselabels.top()<< ":" <<endl;
        elselabels.pop();

    }ELSE s1 = statement
    {
        $act_text = "if (" + $e.act_text + ")" + $s.act_text + "else\n" + $s1.act_text;
        writeIntoparserLogFile("Line " + to_string($s1.stop->getLine()) + ": statement : IF LPAREN expression RPAREN statement ELSE statement\n\n" + $act_text + "\n");
    
        asmFile<<exitlabels.top() <<":"<<"\t\t\t; Line "<< to_string($ELSE->getLine())<<endl;
        exitlabels.pop();
    }
	| WHILE LPAREN
    {
        string looplabel = newlabel();
        looplabels.push(looplabel);
        asmFile <<looplabel<<":"<<endl;
    }e = expression 
    { 
        string exitlabel = newlabel();
        exitlabels.push(exitlabel);
        asmFile << "\tPOP AX"<<"\t\t\t; Line "<< to_string($WHILE->getLine())<<endl;
        asmFile << "\tCMP AX, 0" <<endl;
        asmFile << "\tJE "<<exitlabel<<endl;
    }RPAREN
      s = statement {
        $act_text = "while (" + $e.act_text + ")" + $s.act_text;
        writeIntoparserLogFile("Line " + to_string($s.stop->getLine()) + ": statement : WHILE LPAREN expression RPAREN statement\n\n" + $act_text + "\n");
        asmFile <<"\tJMP "<<looplabels.top()<<endl;
        looplabels.pop();
        asmFile<<exitlabels.top()<<":"<<endl;
        exitlabels.pop();
    }
	| PRINTLN LPAREN ID RPAREN SEMICOLON {
        $act_text = $ctx->getText()+"\n";
        writeIntoparserLogFile("Line " + to_string($PRINTLN->getLine()) + ": statement : PRINTLN LPAREN ID RPAREN SEMICOLON\n");
        if(!Table.getCurrentScopeTable()->lookup($ID->getText()))
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Undeclared variable " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Undeclared variable " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile($act_text + "\n");
        SymbolInfo *item = Table.lookup($ID->getText());
        if(item)
        {
            if(item->getGlobal())
                asmFile << "\tMOV AX, " << item->getName()<<"\t\t\t; Line "<< to_string($ID->getLine()) <<endl;
            else
                asmFile << "\tMOV AX, [BP-" << item->getOffset() << "]" <<endl;

            asmFile << "\tCALL print_output"<<"\t\t\t; Line "<< to_string($ID->getLine()) <<endl;
            asmFile<< "\tCALL new_line"<<endl;
        }
    }
	| RETURN e = expression SEMICOLON {
        $act_text = "return " + $e.act_text + ";\n";
        $line = $SEMICOLON->getLine();
        writeIntoparserLogFile("Line " + to_string($RETURN->getLine()) + ": statement : RETURN expression SEMICOLON\n\n" + $act_text + "\n");
        
        if(returnlabels.empty())
        {    
            string returnlabel = newlabel();
            returnlabels.push(returnlabel);
        }
        asmFile <<"\tPOP AX"<<"\t\t\t; Line "<< to_string($RETURN->getLine())<<endl;    
        asmFile <<"\tJMP "<<returnlabels.top()<<endl; 
    };

expression_statement
	returns[string act_text, int line]:
	SEMICOLON {
        $act_text = $ctx->getText();
        $line = $SEMICOLON->getLine();
        writeIntoparserLogFile("Line " + to_string($SEMICOLON->getLine()) + ": expression_statement : SEMICOLON\n\n" + $act_text + "\n");
    }
	| expression SEMICOLON {
        $act_text = $ctx->getText();
        $line = $SEMICOLON->getLine();
        writeIntoparserLogFile("Line " + to_string($SEMICOLON->getLine()) + ": expression_statement : expression SEMICOLON\n\n" + $act_text + "\n");
        asmFile << "\tPOP AX" <<"\t\t\t; Line "<< to_string($SEMICOLON->getLine())<<endl;
    } 
    | expression a=ANY {
        writeIntoErrorFile("Error at line " + to_string($a->getLine()) + ": syntax error, expected SEMICOLON\n");
        writeIntoparserLogFile("Error at line " + to_string($a->getLine()) + ": syntax error, expected SEMICOLON\n");
         
    }
    ;

variable
	returns[string act_text, string type]:
	ID {
        $act_text = $ctx->getText();
        SymbolInfo* item = Table.lookup($ID->getText());
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": variable : ID\n");
        if (item)
        {
            $type = item->getType();
            int isArray = $type.find(' ');
            if(isArray != string::npos)
            {
                writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Type mismatch, " + $ID->getText() + " is an array\n");
                writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Type mismatch, " + $ID->getText() + " is an array\n");
            } 
        }
        else{
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Undeclared variable " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Undeclared variable " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile($act_text + "\n");
        //writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": variable : ID\n\n" + $act_text + "\n");
    }
	| ID LTHIRD e=expression RTHIRD {
        //$act_text = $ctx->getText();
        $act_text =$ID->getText();
        SymbolInfo* item = Table.getCurrentScopeTable()->lookup($ID->getText());
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": variable : ID LTHIRD expression RTHIRD\n");
        if (item)
        {
            $type = item->getType();
            int pos = $type.find(' ');
            if(pos == string::npos)
            {
                writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": " + $ID->getText() + " not an array\n");
                writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": " + $ID->getText() + " not an array\n");
            }
            $type = $type.substr(0, pos);
        }
        string exp = $e.act_text;
        int isInt = exp.find('.');
        if(isInt != string::npos)
        {
            writeIntoErrorFile("Error at line " + to_string($ID->getLine()) + ": Expression inside third brackets not an integer\n");
            //writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": variable : ID LTHIRD expression RTHIRD\n");
            writeIntoparserLogFile("Error at line " + to_string($ID->getLine()) + ": Expression inside third brackets not an integer\n");
            //writeIntoparserLogFile($act_text + "\n");
        }//else
            //writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": variable : ID LTHIRD expression RTHIRD\n\n" + $act_text + "\n");
        writeIntoparserLogFile($act_text + "\n");
    };

expression
	returns[string act_text, string type]:
	l=logic_expression {

        $act_text = $ctx->getText();
        $type = $l.type ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": expression : logic expression\n\n" + $act_text + "\n");
    }
	| v=variable ASSIGNOP l=logic_expression {
        $act_text = $ctx->getText();
        $type = $v.type ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": expression : variable ASSIGNOP logic_expression\n");
        if($l.type == "void")
        {
            writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Void function used in expression\n");
            writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Void function used in expression\n");
        }
        else if($v.type!= "" && $v.type != $l.type && $v.type == "int")
        {
            writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Type Mismatch\n");
            
            writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Type Mismatch\n");
            
        }//else
            //writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": expression : variable ASSIGNOP logic_expression\n\n" + $act_text + "\n");
            writeIntoparserLogFile($act_text + "\n");


        SymbolInfo* itemglobal = Table.lookup($v.act_text);
        SymbolInfo* item = Table.getCurrentScopeTable()->lookup($v.act_text);

        SymbolInfo* sym = item ? item : itemglobal;

        if(sym){
            bool isLocal = (sym == item);
            bool isGlobal = sym->getGlobal();
            bool isArray = sym->getarray();
            int offset = sym->getOffset();

            if (isArray && isGlobal){
                asmFile << "\tPOP AX" <<"\t\t\t; Line "<< to_string($ASSIGNOP->getLine())<<endl;
                asmFile << "\tPOP BX" << endl;
                asmFile << "\tPUSH AX" << endl;
                asmFile << "\tMOV AX, 2" << endl;
                asmFile << "\tMUL BX" << endl;
                asmFile << "\tMOV BX, AX" <<endl;
                asmFile << "\tPOP AX" <<endl;
                asmFile << "\tMOV " << $v.act_text << "[BX], AX" << endl;
                asmFile << "\tPUSH AX" <<endl;
            }else if(isArray)
            {
                asmFile << "\tPOP AX"<<"\t\t\t; Line "<< to_string($ASSIGNOP->getLine()) << endl;
                asmFile << "\tPOP BX" << endl;
                asmFile << "\tPUSH AX" << endl;
                asmFile << "\tMOV AX, 2" << endl;
                asmFile << "\tMUL BX" << endl;
                asmFile << "\tMOV BX, AX" <<endl;
                asmFile << "\tMOV AX, "<< sym->getarraylen()*2+sym->getOffset()-4 <<endl;
                asmFile << "\tSUB AX, BX"<<endl;
                asmFile << "\tMOV BX, AX"<<endl;
                asmFile << "\tPOP AX" <<endl;
                asmFile << "\tMOV SI, BX "<<endl;
                asmFile << "\tNEG SI" <<endl;
                asmFile << "\tMOV [BP+SI], AX" << endl;
                asmFile << "\tPUSH AX" <<endl;
            }
            else {
                asmFile << "\tPOP AX" <<"\t\t\t; Line "<< to_string($ASSIGNOP->getLine())<< endl;

                if (isGlobal) {
                    asmFile << "\tMOV " << $v.act_text << ", AX" << endl;
                } else {
                    string sign = offset < 0 ? "+" : "-";
                    int absOffset = abs(offset);
                    asmFile << "\tMOV [BP" << sign << absOffset << "], AX" << endl;
                }

                asmFile << "\tPUSH AX" << endl;
            }
        }
    };

logic_expression
	returns[string act_text, string type]:
	r=rel_expression {
        $act_text = $ctx->getText();
        $type = $r.type ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": logic_expression : rel_expression\n\n" + $act_text + "\n");
    }
	| r=rel_expression LOGICOP r1=rel_expression {
        $act_text = $ctx->getText();
        $type = "int" ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": logic_expression : rel_expression LOGICOP rel_expression\n\n" + $act_text + "\n");
    

        asmFile <<"\tPOP BX "<<"\t\t\t; Line "<< to_string($LOGICOP->getLine())<<endl;
        asmFile << "\tPOP AX " <<endl;

        string trueLabel = newlabel();
        string falseLabel = newlabel();

        if($LOGICOP->getText() == "||")
        {
            asmFile<<"\tOR BX, AX"<<endl;
            asmFile<<"\tCMP BX, 0"<<endl;
            asmFile<<"\tJNE "<<trueLabel<<endl;

            asmFile << "\tPUSH 0" <<endl;
            asmFile << "\tJMP " << falseLabel <<endl;
            asmFile << trueLabel << ":" <<endl;
            asmFile << "\tPUSH 1" <<endl;
            asmFile << falseLabel <<":"<<endl<<endl;
        }else if($LOGICOP->getText() == "&&")
        {
            asmFile<<"\tCMP BX, 0"<<endl;
            asmFile<<"\tJE "<<trueLabel<<endl;
            asmFile<<"\tCMP AX, 0"<<endl;
            asmFile<<"\tJE "<<trueLabel<<endl;

            asmFile << "\tPUSH 1" <<endl;
            asmFile << "\tJMP " << falseLabel <<endl;
            asmFile << trueLabel << ":" <<endl;
            asmFile << "\tPUSH 0" <<endl;
            asmFile << falseLabel <<":"<<endl<<endl;
        }
    };

rel_expression
	returns[string act_text, string type]:
	s=simple_expression {
        $act_text = $ctx->getText();
        $type = $s.type ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": rel_expression : simple_expression\n\n" + $act_text + "\n");
    }
	| s=simple_expression RELOP s1=simple_expression {
        $act_text = $ctx->getText();
        string relop = $RELOP->getText();
        $type = "int" ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": rel_expression : simple_expression RELOP simple_expression\n\n" + $act_text + "\n");

        
        asmFile <<"\tPOP BX "<<"\t\t\t; Line "<< to_string($RELOP->getLine())<<endl;
        asmFile << "\tPOP AX " <<endl;
        asmFile <<"\tCMP AX, BX" <<endl;

        string trueLabel = newlabel();
        string falseLabel = newlabel();

        if(relop == "<=")
        {
            asmFile<<"\tJLE "<<trueLabel<<endl;
        }else if(relop == ">=")
        {
            asmFile<<"\tJGE "<<trueLabel<<endl;
        }else if(relop == "<")
        {
            asmFile<<"\tJL "<<trueLabel<<endl;
        }else if(relop == ">")
        {
            asmFile<<"\tJG "<<trueLabel<<endl;
        }else if(relop == "==")
        {
            asmFile<<"\tJE "<<trueLabel<<endl;
        }else if(relop == "!=")
        {
            asmFile<<"\tJNE "<<trueLabel<<endl;
        }

        asmFile << "\tPUSH 0" <<endl;
        asmFile << "\tJMP " << falseLabel <<endl;
        asmFile << trueLabel << ":" <<endl;
        asmFile << "\tPUSH 1" <<endl;
        asmFile << falseLabel <<":"<<endl<<endl;
    };

simple_expression
	returns[string act_text, string type]:
	t=term {
        $act_text = $ctx->getText();
        $type = $t.type ;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": simple_expression : term\n\n" + $act_text + "\n");
    }
	| s=simple_expression ADDOP t=term {
        $act_text = $ctx->getText();
        $type = $t.type ;
        if($s.type == "float" || $t.type == "float")
            $type = "float";
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": simple_expression : simple_expression ADDOP term\n\n" + $act_text + "\n");
        asmFile << "\tPOP BX"<<"\t\t\t; Line "<< to_string($ADDOP->getLine())<<endl;
        asmFile << "\tPOP AX"<<endl;
        if($ADDOP->getText()=="-")
            asmFile << "\tSUB AX, BX"<<endl;
        else
            asmFile << "\tADD AX, BX"<<endl;
        asmFile << "\tPUSH AX"<<endl;
    } 
    |s=simple_expression ADDOP ASSIGNOP t=term
    {
        writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": syntax error, unexpected ASSIGNOP\n");
        writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": syntax error, unexpected ASSIGNOP\n");
    }
    ;

term
	returns[string act_text, string type ]:
	u=unary_expression { $act_text = $ctx->getText() ; $type = $u.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": term : unary_expression \n\n" + $ctx->getText() + "\n");
		}
	| t=term MULOP u=unary_expression { 
        $act_text = $ctx->getText() ;
        $type = $u.type ;
        if($u.type == "float" || $t.type == "float")
            $type = "float";
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": term : term MULOP unary_expression \n");
        if($u.type == "void")
        {
            writeIntoErrorFile( "Error at line " + to_string($ctx->getStart()->getLine()) + ": Void function used in expression\n");
            writeIntoparserLogFile( "Error at line " + to_string($ctx->getStart()->getLine()) + ": Void function used in expression\n");
        }
        if($MULOP->getText()=="%" && ($t.act_text == "0" || $u.act_text == "0"))
        {
            writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Modulus by Zero\n");
            writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Modulus by Zero\n");
        }
        else if ($MULOP->getText()=="%" && ($t.type != "int" || $u.type != "int"))
        {
            writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Non-Integer operand on modulus operator\n");
            
            writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Non-Integer operand on modulus operator\n"); 
            
        }//else
            //writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": term : term MULOP unary_expression \n\n" + $ctx->getText() + "\n");
        writeIntoparserLogFile($ctx->getText() + "\n");

        
        asmFile << "\tPOP BX"<<"\t\t\t; Line "<< to_string($MULOP->getLine())<<endl;
        asmFile << "\tPOP AX"<<endl;
        if($MULOP->getText()=="*")
        {
            asmFile << "\tMUL BX"<<endl;
            asmFile << "\tPUSH AX"<<endl;
        }else if($MULOP->getText()=="/")
        {
            asmFile << "\tMOV DX, 0000H"<<endl;
            asmFile << "\tDIV BX"<<endl;
            asmFile << "\tPUSH AX"<<endl;
        }else if($MULOP->getText()=="%")
        {
            asmFile << "\tMOV DX, 0000H"<<endl;
            asmFile << "\tDIV BX"<<endl;
            asmFile << "\tPUSH DX"<<endl;
        }
	};

unary_expression
	returns[string act_text, string type]:
	ADDOP u=unary_expression { 
        $act_text = $ctx->getText() ; $type = $u.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": unary_expression : ADDOP unary_expression \n\n" + $ctx->getText() + "\n");
        if($ADDOP->getText()=="-")
        {
            asmFile << "\tPOP AX"<<"\t\t\t; Line "<< to_string($ADDOP->getLine())<<endl;
            asmFile << "\tNEG AX"<<endl;
            asmFile << "\tPUSH AX"<<endl;
        }
	}
	| NOT u=unary_expression { $act_text = $ctx->getText() ; $type = $u.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": unary_expression : NOT unary expression \n\n" + $ctx->getText() + "\n");
		}
	| f=factor { $act_text = $ctx->getText() ; $type = $f.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": unary_expression : factor \n\n" + $ctx->getText() + "\n");
		};

factor
	returns[string act_text, string type]:
	v=variable { 
        $act_text = $ctx->getText() ;
        $type = $v.type;
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : variable \n\n" + $ctx->getText() + "\n");     
        
        SymbolInfo* itemglobal = Table.lookup($v.act_text);
        SymbolInfo* item = Table.getCurrentScopeTable()->lookup($v.act_text);

        SymbolInfo* sym = item ? item : itemglobal;

        if(sym){
            bool isLocal = (sym == item);
            bool isGlobal = sym->getGlobal();
            bool isArray = sym->getarray();
            int offset = sym->getOffset();

            if (isArray && isGlobal){
                asmFile << "\tPOP BX"<<"\t\t\t; Line "<< to_string($ctx->getStart()->getLine()) << endl;
                asmFile << "\tSHL BX, 1 "<<endl;
                asmFile << "\tMOV AX, " << $v.act_text << "[BX]" << endl;
                asmFile << "\tPUSH AX "<<endl;           
            }else if(isArray)
            {
                asmFile << "\tPOP BX" <<"\t\t\t; Line "<< to_string($ctx->getStart()->getLine()) << endl;
                asmFile << "\tSHL BX, 1"<< endl;
                asmFile << "\tMOV AX, "<< sym->getarraylen()*2+sym->getOffset()-4 <<endl;
                asmFile << "\tSUB AX, BX"<<endl;
                asmFile << "\tMOV BX, AX"<<endl;
                asmFile << "\tMOV SI, BX "<<endl;
                asmFile << "\tNEG SI" <<endl;
                asmFile << "\tMOV AX, [BP+SI]" << endl;
                asmFile << "\tPUSH AX" <<endl;
            }
            else {
                
                if (isGlobal) {
                    asmFile << "\tPUSH " << sym->getName() <<"\t\t\t; Line "<< to_string($ctx->getStart()->getLine()) << endl;
                } else {
                    string sign = offset < 0 ? "+" : "-";
                    int absOffset = abs(offset);
                    asmFile << "\tPUSH [BP" << sign << absOffset << "]" <<"\t\t; Line "<< to_string($ctx->getStart()->getLine()) << endl;
                }

            }
        }
    }
	| ID LPAREN a=argument_list RPAREN { 
        $act_text = $ctx->getText() ;
        SymbolInfo * item = Table.lookup($ID->getText());
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : ID LPAREN argument_list RPAREN \n");
        if (item)
        {
            $type = item->getReturnType();
            if($a.types.size() != item->getParamTypes().size())
            {
                writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Total number of arguments mismatch in function " + $ID->getText() + "\n");
                writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Total number of arguments mismatch in function " + $ID->getText() + "\n");
            }
            else if($a.types != item->getParamTypes())
            {
                writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": 1th argument mismatch in function " + $ID->getText() + "\n");
                writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": 1th argument mismatch in function " + $ID->getText() + "\n");
            }
        }else
        {
            writeIntoErrorFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Undeclared function " + $ID->getText() + "\n");
            writeIntoparserLogFile("Error at line " + to_string($ctx->getStart()->getLine()) + ": Undeclared function " + $ID->getText() + "\n");
        }
        writeIntoparserLogFile($ctx->getText() + "\n");
        asmFile << "\tCALL "<< $ID->getText()<<"\t\t; Line "<< to_string($ID->getLine())  <<endl;
        asmFile << "\tPUSH AX"<<endl;
	}
	| LPAREN e=expression RPAREN { $act_text = $ctx->getText() ; $type = $e.type; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : LPAREN expression RPAREN \n\n" + $ctx->getText() + "\n");
	}
	| CONST_INT { $act_text = $ctx->getText() ; $type = "int" ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : CONST_INT \n\n" + $ctx->getText() + "\n");
                    asmFile<<"\tPUSH " << $ctx->getText() <<"\t\t\t; Line "<< to_string($ctx->getStart()->getLine())<<endl;
    }
	| CONST_FLOAT { $act_text = $ctx->getText() ; $type = "float" ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : CONST_FLOAT  \n\n" + $CONST_FLOAT->getText() + "\n");
	}
	| v=variable INCOP {
        $act_text = $ctx->getText() ; $type = $v.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : variable INCOP \n\n" + $ctx->getText() + "\n");
        
        SymbolInfo* itemglobal = Table.lookup($v.act_text);
        SymbolInfo* item = Table.getCurrentScopeTable()->lookup($v.act_text);

        SymbolInfo* sym = item ? item : itemglobal;

        if(sym){
            bool isLocal = (sym == item);
            bool isGlobal = sym->getGlobal();
            bool isArray = sym->getarray();
            int offset = sym->getOffset();

            if (isArray && isGlobal){
                asmFile << "\tPOP BX" <<"\t\t\t; Line "<< to_string($INCOP->getLine())<< endl;
                asmFile << "\tSHL BX, 1 "<<endl;
                asmFile << "\tMOV AX, " << $v.act_text << "[BX]" << endl;
                asmFile << "\tPUSH AX "<<endl;
                asmFile << "\tINC AX " <<endl;
                asmFile << "\tMOV "<< $v.act_text << "[BX], AX" << endl;
            }else if(isArray)
            {
                asmFile << "\tPOP BX" <<"\t\t\t; Line "<< to_string($INCOP->getLine())<< endl;
                asmFile << "\tSHL BX, 1"<< endl;
                asmFile << "\tMOV AX, "<< sym->getarraylen()*2+sym->getOffset()-4 <<endl;
                asmFile << "\tSUB AX, BX"<<endl;
                asmFile << "\tMOV BX, AX"<<endl;
                asmFile << "\tMOV SI, BX "<<endl;
                asmFile << "\tNEG SI" <<endl;
                asmFile << "\tMOV AX, [BP+SI]" << endl;
                asmFile << "\tPUSH AX" <<endl;
                asmFile << "\tINC AX"<<endl;
                asmFile << "\tMOV [BP+SI], AX" <<endl;
            }
            else {
                
                if (isGlobal) {
                    asmFile << "\tPUSH " << sym->getName() <<"\t\t\t; Line "<< to_string($INCOP->getLine())<< endl;
                    asmFile << "\tINC " << sym->getName() << endl;
                } else {
                    string sign = offset < 0 ? "+" : "-";
                    int absOffset = abs(offset);
                    string addr = "[BP" + sign + to_string(absOffset) + "]";

                    asmFile << "\tPUSH " << addr <<"\t\t\t; Line "<< to_string($INCOP->getLine())<< endl;
                    asmFile << "\tINC " << addr << endl;
                }
            }
        }
    }
	| v=variable DECOP {
        $act_text = $ctx->getText() ; $type = $v.type ; writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": factor : variable DECOP \n\n" + $ctx->getText() + "\n");
        
        SymbolInfo* itemglobal = Table.lookup($v.act_text);
        SymbolInfo* item = Table.getCurrentScopeTable()->lookup($v.act_text);

        SymbolInfo* sym = item ? item : itemglobal;

        if(sym){
            bool isLocal = (sym == item);
            bool isGlobal = sym->getGlobal();
            bool isArray = sym->getarray();
            int offset = sym->getOffset();

            if (isArray && isGlobal){
                asmFile << "\tPOP BX" <<"\t\t\t; Line "<< to_string($DECOP->getLine())<< endl;
                asmFile << "\tSHL BX, 1 "<<endl;
                asmFile << "\tMOV AX, " << $v.act_text << "[BX]" << endl;
                asmFile << "\tPUSH AX "<<endl;
                asmFile << "\tDEC AX " <<endl;
                asmFile << "\tMOV "<< $v.act_text << "[BX], AX" << endl;
            }else if(isArray)
            {
                asmFile << "\tPOP BX" <<"\t\t\t; Line "<< to_string($DECOP->getLine())<< endl;
                asmFile << "\tSHL BX, 1"<< endl;
                asmFile << "\tMOV AX, "<< sym->getarraylen()*2+sym->getOffset()-4 <<endl;
                asmFile << "\tSUB AX, BX"<<endl;
                asmFile << "\tMOV BX, AX"<<endl;
                asmFile << "\tMOV SI, BX "<<endl;
                asmFile << "\tNEG SI" <<endl;
                asmFile << "\tMOV AX, [BP+SI]" << endl;
                asmFile << "\tPUSH AX" <<endl;
                asmFile << "\tDEC AX"<<endl;
                asmFile << "\tMOV [BP+SI], AX" <<endl;
            }
            else {
                
                if (isGlobal) {
                    asmFile << "\tMOV AX, " << sym->getName() <<"\t\t\t; Line "<< to_string($DECOP->getLine())<< endl;
                    asmFile << "\tPUSH AX" << endl;
                    asmFile << "\tDEC AX "<< endl;
                    asmFile << "\tMOV " << sym->getName() <<", AX" <<endl;
                } else {
                    string sign = offset < 0 ? "+" : "-";
                    int absOffset = abs(offset);
                    string addr = "[BP" + sign + to_string(absOffset) + "]";

                    asmFile << "\tMOV AX, " << addr <<"\t\t\t; Line "<< to_string($DECOP->getLine())<< endl;
                    asmFile << "\tPUSH AX" << endl;
                    asmFile << "\tDEC AX "<< endl;
                    asmFile << "\tMOV " << addr <<", AX" <<endl;
                }
            }
        }
    };

argument_list
	returns[string act_text, vector <string> types]:
	a=arguments {
         $act_text = $ctx->getText() ;
         $types = $a.types;
          writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": argument_list : arguments \n\n" + $ctx->getText() + "\n");
		}
	|;

arguments
	returns[string act_text, vector <string> types]:
	a=arguments COMMA l=logic_expression { 
        $act_text = $ctx->getText() ;
        $types = $a.types;
        $types.push_back($l.type);
        writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": arguments : arguments COMMA logic_expression \n\n" + $ctx->getText() + "\n");
	}
	| l=logic_expression { 
        $act_text = $ctx->getText() ;
        $types.push_back($l.type);
         writeIntoparserLogFile("Line " + to_string($ctx->getStart()->getLine()) + ": arguments : logic_expression \n\n" + $ctx->getText() + "\n");
		};

