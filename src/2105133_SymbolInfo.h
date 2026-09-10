#ifndef SYMBOLINFO_H
#define SYMBOLINFO_H

#include <string>
#include <vector>
using namespace std;

class SymbolInfo
{

private:
    string name;            //private
    string type;
    SymbolInfo* next; // for chaining

    bool isFunction;
    bool isDefined;
    bool isDeclared;
    int offset;
    bool isGlobal;
    bool isarray;
    int arraylen;
    string returnType;
    vector <string> paramTypes;
public:

    SymbolInfo()
    {
        name = "";
        type = "";
        next = nullptr;
        offset= 0 ;
        isFunction = false;
        isDeclared = false;
        isDefined = false;
    }

    SymbolInfo(string name, string type)
    {
        this->name = name;
        this->type = type;
        this->next = nullptr;
        this->offset = 0;
        isFunction = false;
        isDeclared = false;
        isDefined = false;
    }

    string getName()
    {
        return name;
    }

    string getType()
    {
        return type;
    }

    void setName(string& name)
    {
        this->name = name;
    }

    void setType(string& type)
    {
        this->type = type;
    }

    SymbolInfo* getNext()
    {
        return next;
    }

    void setNext(SymbolInfo* next)
    {
        this->next = next;
    }

    bool getIsFunction()
    {
        return isFunction;
    }

    void setIsFunction(bool value)
    {
        isFunction = value;
    }

    bool getIsDefined()
    {
        return isDefined;
    }

    void setIsDefined(bool value)
    {
        isDefined = value;
    }

    bool getIsDeclared()
    {
        return isDeclared;
    }

    void setIsDeclared(bool value)
    {
        isDeclared = value;
    }

    string getReturnType()
    {
        return returnType;
    }

    void setReturnType(string& value)
    {
        returnType = value;
    }

    vector <string> getParamTypes()
    {
        return paramTypes;
    }

    void setParamTypes(vector<string>& value)
    {
        paramTypes = value;
    }

    void addParamType(string & value)
    {
        paramTypes.push_back(value);
    }

    int getOffset()
    {
        return offset;
    }

    void setOffset(int  value)
    {
        offset = value;
    }

    bool getGlobal()
    {
        return isGlobal;
    }

    void setGlobal(bool value)
    {
        isGlobal = value;
    }

    bool getarray()
    {
        return isarray;
    }

    void setarray(bool value)
    {
        isarray = value;
    }

    int getarraylen()
    {
        return arraylen;
    }

    void setarraylen(int  value)
    {
        arraylen = value;
    }

};

#endif
