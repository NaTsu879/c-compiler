#ifndef SCOPETABLE_H
#define SCOPETABLE_H

#include "2105133_SymbolInfo.h"
#include <iostream>
#include <string>
#include <iomanip>
#include <fstream>
using namespace std;

class ScopeTable
{
private:
    SymbolInfo** table;
    int numBuckets;
    int numElements;
    int collisionCount;
    pair<int, int> lastIndex;
    string id;
    ScopeTable* parentScope;

    unsigned int sdbmHash2(const char *p) 
    {
        unsigned int hash = 0;
        auto *str = (unsigned char *) p;
        int c{};
        while ((c = *str++)) {
            hash = c + (hash << 6) + (hash << 16) - hash;
        }
        return hash%numBuckets;
    }

    unsigned int sdbmHash(string& str)
    {
        unsigned int hash = 0;
        unsigned int len = str.length();
        for (unsigned int i = 0; i< len; i++)
        {
            hash = ((str[i]) + (hash<< 6) + (hash<< 16) - hash)% numBuckets;
        }
        return hash;
    }

    unsigned int djb2Hash(string& str)
    {
        unsigned int hash = 5381;
        for (char ch: str)
        {
            //cout<<"here";
            hash = ((hash<< 5) + hash) + ch; // hash * 33 + ch
        }
        return hash% numBuckets;
    }

    unsigned int bkdrHash(string& str)
    {
        unsigned int seed = 131; // 31, 131, 1313, 13131, etc.
        unsigned int hash = 0;
        for (char ch: str)
        {
            hash= hash * seed + ch;
        }
        return hash% numBuckets;
    }

    void rehash()
    {
        int oldNumBuckets = numBuckets;
        numBuckets = numBuckets*2;
        SymbolInfo** oldTable = table;

        table = new SymbolInfo*[numBuckets];
        for (int i = 0; i < numBuckets; ++i)
        {
            table[i] = nullptr;
        }

        numElements = 0;

        for (int i = 0; i < oldNumBuckets; ++i)
        {
            SymbolInfo* curr = oldTable[i];
            while (curr)
            {
                SymbolInfo* next = curr->getNext();
                insert(curr->getName(), curr->getType());
                delete curr;
                curr = next;
            }
        }

        delete[] oldTable;
    }

public:

    typedef unsigned int (ScopeTable::*HashFunction)(string&);

    HashFunction funchash;

    ScopeTable(int n, string id, string hash, ScopeTable* parent = nullptr)
    {
        numBuckets = n;
        this->id = id;
        parentScope = parent;
        numElements = 0;
        lastIndex.first = -1;
        lastIndex.second = -1;
        collisionCount = 0;

        if (hash == "sdbm")
        {
            //cout<<"here";
            funchash = &ScopeTable::sdbmHash;
        }
        else if (hash == "djb2")
        {
            //cout<<"here";
            funchash = &ScopeTable::djb2Hash;
        }
        else if (hash == "bkdr")
        {
            //cout<<"here";
            funchash = &ScopeTable::bkdrHash;
        }
        else
        {
            cerr << "Wrong hash function name";
        }

        table = new SymbolInfo*[numBuckets];
        for (int i = 0; i < numBuckets; ++i)
        {
            table[i] = nullptr;
        }
    }

    ~ScopeTable()
    {
        for (int i = 0; i< numBuckets; i++)
        {
            SymbolInfo* entry = table[i];
            while (entry)
            {
                SymbolInfo* temp = entry;
                entry = entry->getNext();
                delete temp;
            }
        }
        delete[] table;
    }

    string getID() const
    {
        return id;
    }

    ScopeTable* getParentScope() const
    {
        return parentScope;
    }

    bool insert(string name, string type)
    {
        if (lookup(name))
        {
            return false;
        }

        if (numElements+1 > numBuckets)
        {
            //rehash();
        }

        //int idx = (this->*funchash)(name);
        int idx = sdbmHash2(name.c_str());
        SymbolInfo* head = table[idx];
        lastIndex.first = idx;

        SymbolInfo* newSymbol = new SymbolInfo(name, type);

        if (head == nullptr)
        {
            table[idx] = newSymbol;
            lastIndex.second = 0;
        }
        else
        {
            collisionCount++;
            int chainPos = 0;
            SymbolInfo* temp = head;
            while (temp->getNext() != nullptr)
            {
                temp = temp->getNext();
                chainPos++;
            }
            temp->setNext(newSymbol);
            lastIndex.second = chainPos + 1;
        }

        numElements++;
        return true;
    }

    SymbolInfo* lookup(string name)
    {
        //int idx = (this->*funchash)(name);
        int idx = sdbmHash2(name.c_str());
        SymbolInfo* curr = table[idx];
        lastIndex.first = idx;
        int temp = 0;
        while (curr)
        {
            if (curr->getName() == name)
            {
                lastIndex.second = temp;
                return curr;
            }
            curr = curr->getNext();
            temp++;
        }
        lastIndex.second = -1;
        return nullptr;
    }

    bool remove(string name)
    {
        //int idx = (this->*funchash)(name);
        int idx = sdbmHash2(name.c_str());
        SymbolInfo* curr = table[idx];
        lastIndex.first = idx;
        SymbolInfo* prev = nullptr;
        int temp = 0;
        while (curr)
        {
            if (curr->getName() == name)
            {
                if (prev) prev->setNext(curr->getNext());
                else table[idx] = curr->getNext();
                delete curr;
                --numElements;
                lastIndex.second = temp;
                return true;
            }
            temp++;
            prev = curr;
            curr = curr->getNext();
        }
        return false;
    }

    void print(ofstream &fout, int indent = 0)
    {
        string indentStr(indent, '\t');
        fout << indentStr << "ScopeTable # " << id << endl;
        for (int i = 0; i < numBuckets; i++)
        {
            
            SymbolInfo* curr = table[i];
            if(curr) fout << indentStr << i  << " --> ";
            while (curr)
            {
                fout << "< " << curr->getName() << " : " << curr->getType() << " >";
                curr = curr->getNext();
                if(!curr) fout << endl;
            }
           
            
        }
    }

    pair<int, int> getlastIndex()
    {
        return lastIndex;
    }

    float HashtableQuality()
    {
        return collisionCount/(float)numBuckets;
    }
};

#endif
