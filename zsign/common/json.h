#ifndef JSON_INCLUDED
#define JSON_INCLUDED

#ifdef _WIN32

typedef signed char int8_t;
typedef short int int16_t;
typedef int int32_t;
typedef long long int int64_t;
typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long int uint64_t;

#else

#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#endif

#include <map>
#include <queue>
#include <vector>
#include <string>
#include <string.h>
#include <limits>
#include <algorithm>
#include <cinttypes>
using namespace std;



class JValue
{
public:
	enum TYPE
	{
		E_NULL = 0,
		E_INT,
		E_BOOL,
		E_FLOAT,
		E_ARRAY,
		E_OBJECT,
		E_STRING,
		E_DATE,
		E_DATA,
	};

public:
	JValue(TYPE type = E_NULL);
	JValue(int val);
	JValue(bool val);
	JValue(double val);
	JValue(int64_t val);
	JValue(const char *val);
	JValue(const string &val);
	JValue(const JValue &other);
	JValue(const char *val, size_t len);
	~JValue();

public:
	int asInt() const;
	bool asBool() const;
	double asFloat() const;
	int64_t asInt64() const;
	string asString() const;
	const char *asCString() const;
	time_t asDate() const;
	string asData() const;

	void assignData(const char *val, size_t size);
	void assignDate(time_t val);
	void assignDateString(time_t val);

	TYPE type() const;
	size_t size() const;
	void clear();

	JValue &at(int index);
	JValue &at(size_t index);
	JValue &at(const char *key);

	bool has(const char *key) const;
	int index(const char *ele) const;
	bool keys(vector<string> &arrKeys) const;

	bool join(JValue &jv);
	bool append(JValue &jv);

	bool remove(int index);
	bool remove(size_t index);
	bool remove(const char *key);

	JValue &back();
	JValue &front();

	bool push_back(int val);
	bool push_back(bool val);
	bool push_back(double val);
	bool push_back(int64_t val);
	bool push_back(const char *val);
	bool push_back(const string &val);
	bool push_back(const JValue &jval);
	bool push_back(const char *val, size_t len);

	bool isInt() const;
	bool isNull() const;
	bool isBool() const;
	bool isFloat() const;
	bool isArray() const;
	bool isObject() const;
	bool isString() const;
	bool isEmpty() const;
	bool isData() const;
	bool isDate() const;
	bool isDataString() const;
	bool isDateString() const;

	operator int() const;
	operator bool() const;
	operator double() const;
	operator int64_t() const;
	operator string() const;
	operator const char *() const;

	JValue &operator=(const JValue &other);

	JValue &operator[](int index);
	const JValue &operator[](int index) const;

	JValue &operator[](size_t index);
	const JValue &operator[](size_t index) const;

	JValue &operator[](int64_t index);
	const JValue &operator[](int64_t index) const;

	JValue &operator[](const char *key);
	const JValue &operator[](const char *key) const;

	JValue &operator[](const string &key);
	const JValue &operator[](const string &key) const;

	friend bool operator==(const JValue &jv, const char *psz)
	{
		return (0 == strcmp(jv.asCString(), psz));
	}

	friend bool operator==(const char *psz, const JValue &jv)
	{
		return (0 == strcmp(jv.asCString(), psz));
	}

	friend bool operator!=(const JValue &jv, const char *psz)
	{
		return (0 != strcmp(jv.asCString(), psz));
	}

	friend bool operator!=(const char *psz, const JValue &jv)
	{
		return (0 != strcmp(jv.asCString(), psz));
	}

private:
	void Free();
	char *NewString(const char *cstr);
	void CopyValue(const JValue &src);
	bool WriteDataToFile(const char *file, const char *data, size_t len);

public:
	static const JValue null;
	static const string nullData;

private:
	union HOLD {
		bool vBool;
		double vFloat;
		int64_t vInt64;
		char *vString;
		vector<JValue> *vArray;
		map<string, JValue> *vObject;
		time_t vDate;
		string *vData;
		wchar_t *vUnicode;
	} m_Value;

	TYPE m_eType;

public:
	string write() const;
	const char *write(string &strDoc) const;

	string styleWrite() const;
	const char *styleWrite(string &strDoc) const;

	bool read(const char *pdoc, string *pstrerr = NULL);
	bool read(const string &strdoc, string *pstrerr = NULL);

	string writePList() const;
	const char *writePList(string &strDoc) const;

	bool readPList(const string &strdoc, string *pstrerr = NULL);
	bool readPList(const char *pdoc, size_t len = 0, string *pstrerr = NULL);

	bool readFile(const char *file, string *pstrerr = NULL);
	bool readPListFile(const char *file, string *pstrerr = NULL);

	bool writeFile(const char *file);
	bool writePListFile(const char *file);
	bool styleWriteFile(const char *file);

	bool readPath(const char *path, ...);
	bool readPListPath(const char *path, ...);
	bool writePath(const char *path, ...);
	bool writePListPath(const char *path, ...);
	bool styleWritePath(const char *path, ...);
};

class JReader
{
public:
	bool parse(const char *pdoc, JValue &root);
	void error(string &strmsg) const;

private:
	struct Token
	{
		enum TYPE
		{
			E_Error = 0,
			E_End,
			E_Null,
			E_True,
			E_False,
			E_Number,
			E_String,
			E_ArrayBegin,
			E_ArrayEnd,
			E_ObjectBegin,
			E_ObjectEnd,
			E_ArraySeparator,
			E_MemberSeparator
		};
		TYPE type;
		const char *pbeg;
		const char *pend;
	};

	void skipSpaces();
	void skipComment();

	bool match(const char *pattern, int patternLength);

	bool readToken(Token &token);
	bool readValue(JValue &jval);
	bool readArray(JValue &jval);
	void readNumber();

	bool readString();
	bool readObject(JValue &jval);

	bool decodeNumber(Token &token, JValue &jval);
	bool decodeString(Token &token, string &decoded);
	bool decodeDouble(Token &token, JValue &jval);

	char GetNextChar();
	bool addError(const string &message, const char *ploc);

private:
	const char *m_pBeg;
	const char *m_pEnd;
	const char *m_pCur;
	const char *m_pErr;
	string m_strErr;
};

class JWriter
{
public:
	static void FastWrite(const JValue &jval, string &strDoc);
	static void FastWriteValue(const JValue &jval, string &strDoc);

public:
	const string &StyleWrite(const JValue &jval);

private:
	void PushValue(const string &strval);
	void StyleWriteValue(const JValue &jval);
	void StyleWriteArrayValue(const JValue &jval);
	bool isMultineArray(const JValue &jval);

public:
	static string v2s(double val);
	static string v2s(int64_t val);
	static string v2s(const char *val);

	static string vstring2s(const char *val);
	static string d2s(time_t t);

private:
	string m_strDoc;
	string m_strTab;
	bool m_bAddChild;
	vector<string> m_childValues;
};

//////////////////////////////////////////////////////////////////////////
class PReader
{
public:
	PReader();

public:
	bool parse(const char *pdoc, size_t len, JValue &root);
	void error(string &strmsg) const;

private:
	struct Token
	{
		enum TYPE
		{
			E_Error = 0,
			E_End,
			E_Null,
			E_True,
			E_False,
			E_Key,
			E_Data,
			E_Date,
			E_Integer,
			E_Real,
			E_String,
			E_ArrayBegin,
			E_ArrayEnd,
			E_ArrayNull,
			E_DictionaryBegin,
			E_DictionaryEnd,
			E_DictionaryNull,
			E_ArraySeparator,
			E_MemberSeparator
		};

		Token()
		{
			pbeg = NULL;
			pend = NULL;
			type = E_Error;
		}

		TYPE type;
		const char *pbeg;
		const char *pend;
	};

	bool readToken(Token &token);
	bool readLabel(string &label);
	bool readValue(JValue &jval, Token &token);
	bool readArray(JValue &jval);
	bool readNumber();

	bool readString();
	bool readDictionary(JValue &jval);

	void endLabel(Token &token, const char *szLabel);

	bool decodeNumber(Token &token, JValue &jval);
	bool decodeString(Token &token, string &decoded, bool filter = true);
	bool decodeDouble(Token &token, JValue &jval);

	void skipSpaces();
	bool addError(const string &message, const char *ploc);

public:
	bool parseBinary(const char *pbdoc, size_t len, JValue &pv);

private:
	uint32_t getUInt24FromBE(const char *v);
	void byteConvert(uint8_t *v, size_t size);
	uint64_t getUIntVal(const char *v, size_t size);
	bool readUIntSize(const char *&pcur, size_t &size);
	bool readBinaryValue(const char *&pcur, JValue &pv);
	bool readUnicode(const char *pcur, size_t size, JValue &pv);

public:
	static void XMLUnescape(string &strval);

private: //xml
	const char *m_pBeg;
	const char *m_pEnd;
	const char *m_pCur;
	const char *m_pErr;
	string m_strErr;

private: //binary
	const char *m_pTrailer;
	uint64_t m_uObjects;
	uint8_t m_uOffsetSize;
	const char *m_pOffsetTable;
	uint8_t m_uDictParamSize;
};

class PWriter
{
public:
	static void FastWrite(const JValue &pval, string &strdoc);
	static void FastWriteValue(const JValue &pval, string &strdoc, string &strindent);

public:
	static void XMLEscape(string &strval);
	static string &StringReplace(string &context, const string &from, const string &to);
};

#endif // JSON_INCLUDED
