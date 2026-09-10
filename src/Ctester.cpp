#include <iostream>
#include <fstream>
#include <string>
#include <stack>
#include "antlr4-runtime.h"
#include "C2105133Lexer.h"
#include "C2105133Parser.h"
#include "2105133_SymbolTable.h"
using namespace antlr4;
using namespace std;

ofstream parserLogFile; // global output stream
ofstream errorFile; // global error stream
ofstream lexLogFile; // global lexer log stream
ofstream asmFile;
ifstream libFile;
SymbolTable Table(40,parserLogFile,"sdbm");
int syntaxErrorCount;
int offset = 2;
int labelcount =0;
int retcount = 0;
stack<string> elselabels;
stack<string> exitlabels;
stack<string> looplabels;
stack<string> inclabels;
stack<string> backlabels;
stack<string> returnlabels;
int main(int argc, const char* argv[]) {
    if (argc < 2) {
        cerr << "Usage: " << argv[0] << " <input_file>" << endl;
        return 1;
    }

    // ---- Input File ----
    ifstream inputFile(argv[1]);
    if (!inputFile.is_open()) {
        cerr << "Error opening input file: " << argv[1] << endl;
        return 1;
    }

    string outputDirectory = "output/";
    string parserLogFileName = outputDirectory + "parserLog.txt";
    string errorFileName = outputDirectory + "errorLog.txt";
    string lexLogFileName = outputDirectory + "lexerLog.txt";
    string asmFileName = outputDirectory + "asmFile.asm";
    string libFileName = "library.txt";
    // create output directory if it doesn't exist
    system(("mkdir -p " + outputDirectory).c_str());

    // ---- Output Files ----
    parserLogFile.open(parserLogFileName);
    if (!parserLogFile.is_open()) {
        cerr << "Error opening parser log file: " << parserLogFileName << endl;
        return 1;
    }

    errorFile.open(errorFileName);
    if (!errorFile.is_open()) {
        cerr << "Error opening error log file: " << errorFileName << endl;
        return 1;
    }

    lexLogFile.open(lexLogFileName);
    if (!lexLogFile.is_open()) {
        cerr << "Error opening lexer log file: " << lexLogFileName << endl;
        return 1;
    }

    asmFile.open(asmFileName);
    if (!asmFile.is_open()) {
        cerr << "Error opening lexer log file: " << asmFileName << endl;
        return 1;
    }
    
    libFile.open(libFileName);
    if (!libFile.is_open()) {
        cerr << "Error opening lexer log file: " << libFileName << endl;
        return 1;
    }
    // ---- Parsing Flow ----
    ANTLRInputStream input(inputFile);
    C2105133Lexer lexer(&input);
    CommonTokenStream tokens(&lexer);
    C2105133Parser parser(&tokens);

    // this is necessary to avoid the default error listener and use our custom error handling
    parser.removeErrorListeners();
    
    // start parsing at the 'start' rule
    parser.start();

    // clean up
    inputFile.close();
    parserLogFile.close();
    errorFile.close();
    lexLogFile.close();
    asmFile.close();
    libFile.close();
    cout << "Parsing completed. Check the output files for details." << endl;

    return 0;
}
