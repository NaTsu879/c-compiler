antlr4 -v 4.13.2 -Dlanguage=Cpp C2105133Lexer.g4
antlr4 -v 4.13.2 -Dlanguage=Cpp C2105133Parser.g4
g++ -std=c++17 -w -I/usr/local/include/antlr4-runtime -c C2105133Lexer.cpp C2105133Parser.cpp Ctester.cpp
g++ -std=c++17 -w C2105133Lexer.o C2105133Parser.o Ctester.o -L/usr/local/lib/ -lantlr4-runtime -o Ctester.out -pthread
LD_LIBRARY_PATH=/usr/local/lib ./Ctester.out $1
