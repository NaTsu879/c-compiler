// File: SymbolTable.h

#ifndef SYMBOLTABLE_H
#define SYMBOLTABLE_H

#include "2105133_ScopeTable.h"
#include <stack>
#include <sstream>
#include <string>
#include <cstdio>
#include <initializer_list>
#include <fstream>

class SymbolTable {
private:
    ScopeTable* current;
    int bucketSize;
    int scopeCounter;
    float deletedRatio;
    ofstream* fout;
    string hash;

public:
    SymbolTable(int numBuckets, ofstream &zout, string hash_function)
    {
        bucketSize = numBuckets;
        scopeCounter = 1;
        deletedRatio = 0.0;
        hash = hash_function;
        stringstream ss;
        ss << scopeCounter;
        fout = &zout;
        current = new ScopeTable(bucketSize, ss.str(), hash);
    }

    ~SymbolTable()
     {
        while (current)
        {
            ScopeTable* temp = current->getParentScope();
            *fout<<"\t"<<"ScopeTable# "<<current->getID()<<" removed"<<endl;

            delete current;
            current = temp;
        }
    }

    void enterScope()
     {
        scopeCounter++;
        stringstream ss;
        ss << scopeCounter-1;
        ScopeTable* newScope = new ScopeTable(bucketSize, current->getID()+"."+ss.str(),hash, current);
        current = newScope;
    }

    bool exitScope()
    {
        if (current->getParentScope()) {
            deletedRatio = deletedRatio + current->HashtableQuality();
            ScopeTable* temp = current;
            current = current->getParentScope();
            delete temp;
            return 1;
        }else return 0;
    }

    bool insert(string name, string type)
    {
        return current->insert(name, type);
    }

    bool remove(string name)
    {
        return current->remove(name);
    }

    SymbolInfo* lookup(string name)
    {
        ScopeTable* temp = current;
        while (temp) {

            SymbolInfo* found = temp->lookup(name);

            if (found)
            {
                //*fout <<"\t"<<"'"<<name<<"'"<<" found in ScopeTable# "<<temp->getID()<<" at position "<<temp->getlastIndex().first+1<<", "<<temp->getlastIndex().second+1<<endl;
                return found;
            }
            temp = temp->getParentScope();
        }
        //*fout <<"\t"<<"'"<<name<<"'"<<" not found in any of the ScopeTables" << endl;
        return nullptr;
    }

    void printCurrentScopeTable(ofstream &fout)
     {
        current->print(fout);
    }

    void printAllScopeTable(ofstream &fout)
     {
        ScopeTable* temp = current;
        int indent =0 ;
        while (temp) {
            temp->print(fout,indent);
            temp = temp->getParentScope();
            //indent++;
            if(temp)
                fout<<"\n\n\n";
        }
        fout<<endl<<endl;
    }

    string getCurrentScopeID(){
        if(current)
        {
            return current->getID();
        }
        return nullptr;
    }

    ScopeTable* getCurrentScopeTable()
    {
        return current;
    }

    float meanratio()
    {
        float answer=deletedRatio;
        int tableCount = scopeCounter ;
        ScopeTable* temp = current;
        while (temp) {
            //cout<<"here";
            answer = answer + temp->HashtableQuality();
            temp = temp->getParentScope();
        }

        return answer/(float)tableCount;
    }

};

#endif
