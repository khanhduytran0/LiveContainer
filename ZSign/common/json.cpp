#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#include <stdarg.h>
#include <inttypes.h>
#include <math.h>
#include <sys/stat.h>
#include "base64.h"

#ifndef WIN32
#define _atoi64(val) strtoll(val, NULL, 10)
#endif

const JValue JValue::null;
const string JValue::nullData;

JValue::JValue(TYPE type) : m_eType(type)
{
	m_Value.vFloat = 0;
}

JValue::JValue(int val) : m_eType(E_INT)
{
	m_Value.vInt64 = val;
}

JValue::JValue(int64_t val) : m_eType(E_INT)
{
	m_Value.vInt64 = val;
}

JValue::JValue(bool val) : m_eType(E_BOOL)
{
	m_Value.vBool = val;
}

JValue::JValue(double val) : m_eType(E_FLOAT)
{
	m_Value.vFloat = val;
}

JValue::JValue(const char *val) : m_eType(E_STRING)
{
	m_Value.vString = NewString(val);
}

JValue::JValue(const string &val) : m_eType(E_STRING)
{
	m_Value.vString = NewString(val.c_str());
}

JValue::JValue(const JValue &other)
{
	CopyValue(other);
}

JValue::JValue(const char *val, size_t len) : m_eType(E_DATA)
{
	m_Value.vData = new string();
	m_Value.vData->append(val, len);
}

JValue::~JValue()
{
	Free();
}

void JValue::clear()
{
	Free();
}

bool JValue::isInt() const
{
	return (E_INT == m_eType);
}

bool JValue::isNull() const
{
	return (E_NULL == m_eType);
}

bool JValue::isBool() const
{
	return (E_BOOL == m_eType);
}

bool JValue::isFloat() const
{
	return (E_FLOAT == m_eType);
}

bool JValue::isString() const
{
	return (E_STRING == m_eType);
}

bool JValue::isArray() const
{
	return (E_ARRAY == m_eType);
}

bool JValue::isObject() const
{
	return (E_OBJECT == m_eType);
}

bool JValue::isEmpty() const
{
	switch (m_eType)
	{
	case E_NULL:
		return true;
		break;
	case E_INT:
		return (0 == m_Value.vInt64);
		break;
	case E_BOOL:
		return (false == m_Value.vBool);
		break;
	case E_FLOAT:
		return (0 == m_Value.vFloat);
		break;
	case E_ARRAY:
	case E_OBJECT:
		return (0 == size());
		break;
	case E_STRING:
		return (0 == strlen(asCString()));
	case E_DATE:
		return (0 == m_Value.vDate);
		break;
	case E_DATA:
		return (NULL == m_Value.vData) ? true : m_Value.vData->empty();
		break;
	}
	return true;
}

JValue::operator const char *() const
{
	return asCString();
}

JValue::operator int() const
{
	return asInt();
}

JValue::operator int64_t() const
{
	return asInt64();
}

JValue::operator double() const
{
	return asFloat();
}

JValue::operator string() const
{
	return asCString();
}

JValue::operator bool() const
{
	return asBool();
}

char *JValue::NewString(const char *cstr)
{
	char *str = NULL;
	if (NULL != cstr)
	{
		size_t len = (strlen(cstr) + 1) * sizeof(char);
		str = (char *)malloc(len);
		memcpy(str, cstr, len);
	}
	return str;
}

void JValue::CopyValue(const JValue &src)
{
	m_eType = src.m_eType;
	switch (m_eType)
	{
	case E_ARRAY:
		m_Value.vArray = (NULL == src.m_Value.vArray) ? NULL : new vector<JValue>(*(src.m_Value.vArray));
		break;
	case E_OBJECT:
		m_Value.vObject = (NULL == src.m_Value.vObject) ? NULL : new map<string, JValue>(*(src.m_Value.vObject));
		break;
	case E_STRING:
		m_Value.vString = (NULL == src.m_Value.vString) ? NULL : NewString(src.m_Value.vString);
		break;
	case E_DATA:
	{
		if (NULL != src.m_Value.vData)
		{
			m_Value.vData = new string();
			*m_Value.vData = *src.m_Value.vData;
		}
		else
		{
			m_Value.vData = NULL;
		}
	}
	break;
	default:
		m_Value = src.m_Value;
		break;
	}
}

void JValue::Free()
{
	switch (m_eType)
	{
	case E_INT:
	{
		m_Value.vInt64 = 0;
	}
	break;
	case E_BOOL:
	{
		m_Value.vBool = false;
	}
	break;
	case E_FLOAT:
	{
		m_Value.vFloat = 0.0;
	}
	break;
	case E_STRING:
	{
		if (NULL != m_Value.vString)
		{
			free(m_Value.vString);
			m_Value.vString = NULL;
		}
	}
	break;
	case E_ARRAY:
	{
		if (NULL != m_Value.vArray)
		{
			delete m_Value.vArray;
			m_Value.vArray = NULL;
		}
	}
	break;
	case E_OBJECT:
	{
		if (NULL != m_Value.vObject)
		{
			delete m_Value.vObject;
			m_Value.vObject = NULL;
		}
	}
	break;
	case E_DATE:
	{
		m_Value.vDate = 0;
	}
	break;
	case E_DATA:
	{
		if (NULL != m_Value.vData)
		{
			delete m_Value.vData;
			m_Value.vData = NULL;
		}
	}
	break;
	default:
		break;
	}
	m_eType = E_NULL;
}

JValue &JValue::operator=(const JValue &other)
{
	if (this != &other)
	{
		Free();
		CopyValue(other);
	}
	return (*this);
}

JValue::TYPE JValue::type() const
{
	return m_eType;
}

int JValue::asInt() const
{
	return (int)asInt64();
}

int64_t JValue::asInt64() const
{
	switch (m_eType)
	{
	case E_INT:
		return m_Value.vInt64;
		break;
	case E_BOOL:
		return m_Value.vBool ? 1 : 0;
		break;
	case E_FLOAT:
		return int(m_Value.vFloat);
		break;
	case E_STRING:
		return _atoi64(asCString());
		break;
	default:
		break;
	}
	return 0;
}

double JValue::asFloat() const
{
	switch (m_eType)
	{
	case E_INT:
		return double(m_Value.vInt64);
		break;
	case E_BOOL:
		return m_Value.vBool ? 1.0 : 0.0;
		break;
	case E_FLOAT:
		return m_Value.vFloat;
		break;
	case E_STRING:
		return atof(asCString());
		break;
	default:
		break;
	}
	return 0.0;
}

bool JValue::asBool() const
{
	switch (m_eType)
	{
	case E_BOOL:
		return m_Value.vBool;
		break;
	case E_INT:
		return (0 != m_Value.vInt64);
		break;
	case E_FLOAT:
		return (0.0 != m_Value.vFloat);
		break;
	case E_ARRAY:
		return (NULL == m_Value.vArray) ? false : (m_Value.vArray->size() > 0);
		break;
	case E_OBJECT:
		return (NULL == m_Value.vObject) ? false : (m_Value.vObject->size() > 0);
		break;
	case E_STRING:
		return (NULL == m_Value.vString) ? false : (strlen(m_Value.vString) > 0);
		break;
	case E_DATE:
		return (m_Value.vDate > 0);
		break;
	case E_DATA:
		return (NULL == m_Value.vData) ? false : (m_Value.vData->size() > 0);
		break;
	default:
		break;
	}
	return false;
}

string JValue::asString() const
{
	switch (m_eType)
	{
	case E_BOOL:
		return m_Value.vBool ? "true" : "false";
		break;
	case E_INT:
	{
		char buf[256];
		sprintf(buf, "%" PRId64, m_Value.vInt64);
		return buf;
	}
	break;
	case E_FLOAT:
	{
		char buf[256];
		sprintf(buf, "%lf", m_Value.vFloat);
		return buf;
	}
	break;
	case E_ARRAY:
		return "array";
		break;
	case E_OBJECT:
		return "object";
		break;
	case E_STRING:
		return (NULL == m_Value.vString) ? "" : m_Value.vString;
		break;
	case E_DATE:
		return "date";
		break;
	case E_DATA:
		return "data";
		break;
	default:
		break;
	}
	return "";
}

const char *JValue::asCString() const
{
	if (E_STRING == m_eType && NULL != m_Value.vString)
	{
		return m_Value.vString;
	}
	return "";
}

size_t JValue::size() const
{
	switch (m_eType)
	{
	case E_ARRAY:
		return (NULL == m_Value.vArray) ? 0 : m_Value.vArray->size();
		break;
	case E_OBJECT:
		return (NULL == m_Value.vObject) ? 0 : m_Value.vObject->size();
		break;
	case E_DATA:
		return (NULL == m_Value.vData) ? 0 : m_Value.vData->size();
		break;
	default:
		break;
	}
	return 0;
}

JValue &JValue::operator[](int index)
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

const JValue &JValue::operator[](int index) const
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

JValue &JValue::operator[](int64_t index)
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

const JValue &JValue::operator[](int64_t index) const
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

JValue &JValue::operator[](size_t index)
{
	if (E_ARRAY != m_eType || NULL == m_Value.vArray)
	{
		Free();
		m_eType = E_ARRAY;
		m_Value.vArray = new vector<JValue>();
	}

	size_t sum = m_Value.vArray->size();
	if (sum <= index)
	{
		size_t fill = index - sum;
		for (size_t i = 0; i <= fill; i++)
		{
			m_Value.vArray->push_back(null);
		}
	}

	return m_Value.vArray->at(index);
}

const JValue &JValue::operator[](size_t index) const
{
	if (E_ARRAY == m_eType && NULL != m_Value.vArray)
	{
		if (index < m_Value.vArray->size())
		{
			return m_Value.vArray->at(index);
		}
	}
	return null;
}

JValue &JValue::operator[](const string &key)
{
	return (*this)[key.c_str()];
}

const JValue &JValue::operator[](const string &key) const
{
	return (*this)[key.c_str()];
}

JValue &JValue::operator[](const char *key)
{
	map<string, JValue>::iterator it;
	if (E_OBJECT != m_eType || NULL == m_Value.vObject)
	{
		Free();
		m_eType = E_OBJECT;
		m_Value.vObject = new map<string, JValue>();
	}
	else
	{
		it = m_Value.vObject->find(key);
		if (it != m_Value.vObject->end())
		{
			return it->second;
		}
	}
	it = m_Value.vObject->insert(m_Value.vObject->end(), make_pair(key, null));
	return it->second;
}

const JValue &JValue::operator[](const char *key) const
{
	if (E_OBJECT == m_eType && NULL != m_Value.vObject)
	{
		map<string, JValue>::const_iterator it = m_Value.vObject->find(key);
		if (it != m_Value.vObject->end())
		{
			return it->second;
		}
	}
	return null;
}

bool JValue::has(const char *key) const
{
	if (E_OBJECT == m_eType && NULL != m_Value.vObject)
	{
		if (m_Value.vObject->end() != m_Value.vObject->find(key))
		{
			return true;
		}
	}

	return false;
}

int JValue::index(const char *ele) const
{
	if (E_ARRAY == m_eType && NULL != m_Value.vArray)
	{
		for (size_t i = 0; i < m_Value.vArray->size(); i++)
		{
			if (ele == (*m_Value.vArray)[i].asString())
			{
				return (int)i;
			}
		}
	}

	return -1;
}

JValue &JValue::at(int index)
{
	return (*this)[index];
}

JValue &JValue::at(size_t index)
{
	return (*this)[index];
}

JValue &JValue::at(const char *key)
{
	return (*this)[key];
}

bool JValue::remove(int index)
{
	if (index >= 0)
	{
		return remove((size_t)index);
	}
	return false;
}

bool JValue::remove(size_t index)
{
	if (E_ARRAY == m_eType && NULL != m_Value.vArray)
	{
		if (index < m_Value.vArray->size())
		{
			m_Value.vArray->erase(m_Value.vArray->begin() + index);
			return true;
		}
	}
	return false;
}

bool JValue::remove(const char *key)
{
	if (E_OBJECT == m_eType && NULL != m_Value.vObject)
	{
		if (m_Value.vObject->end() != m_Value.vObject->find(key))
		{
			m_Value.vObject->erase(key);
			return !has(key);
		}
	}
	return false;
}

bool JValue::keys(vector<string> &arrKeys) const
{
	if (E_OBJECT == m_eType && NULL != m_Value.vObject)
	{
		arrKeys.reserve(m_Value.vObject->size());
		map<string, JValue>::iterator itbeg = m_Value.vObject->begin();
		map<string, JValue>::iterator itend = m_Value.vObject->end();
		for (; itbeg != itend; itbeg++)
		{
			arrKeys.push_back((itbeg->first).c_str());
		}
		return true;
	}
	return false;
}

string JValue::write() const
{
	string strDoc;
	return write(strDoc);
}

const char *JValue::write(string &strDoc) const
{
	strDoc.clear();
	JWriter::FastWrite((*this), strDoc);
	return strDoc.c_str();
}

bool JValue::read(const string &strdoc, string *pstrerr)
{
	return read(strdoc.c_str(), pstrerr);
}

bool JValue::read(const char *pdoc, string *pstrerr)
{
	JReader reader;
	bool bret = reader.parse(pdoc, *this);
	if (!bret)
	{
		if (NULL != pstrerr)
		{
			reader.error(*pstrerr);
		}
	}
	return bret;
}

JValue &JValue::front()
{
	if (E_ARRAY == m_eType)
	{
		if (size() > 0)
		{
			return *(m_Value.vArray->begin());
		}
	}
	else if (E_OBJECT == m_eType)
	{
		if (size() > 0)
		{
			return m_Value.vObject->begin()->second;
		}
	}
	return (*this);
}

JValue &JValue::back()
{
	if (E_ARRAY == m_eType)
	{
		if (size() > 0)
		{
			return *(m_Value.vArray->rbegin());
		}
	}
	else if (E_OBJECT == m_eType)
	{
		if (size() > 0)
		{
			return m_Value.vObject->rbegin()->second;
		}
	}
	return (*this);
}

bool JValue::join(JValue &jv)
{
	if ((E_OBJECT == m_eType || E_NULL == m_eType) && E_OBJECT == jv.type())
	{
		vector<string> arrKeys;
		jv.keys(arrKeys);
		for (size_t i = 0; i < arrKeys.size(); i++)
		{
			(*this)[arrKeys[i]] = jv[arrKeys[i]];
		}
		return true;
	}
	else if ((E_ARRAY == m_eType || E_NULL == m_eType) && E_ARRAY == jv.type())
	{
		size_t count = this->size();
		for (size_t i = 0; i < jv.size(); i++)
		{
			(*this)[count] = jv[i];
			count++;
		}
		return true;
	}

	return false;
}

bool JValue::append(JValue &jv)
{
	if (E_ARRAY == m_eType || E_NULL == m_eType)
	{
		(*this)[((this->size() > 0) ? this->size() : 0)] = jv;
		return true;
	}
	return false;
}

bool JValue::push_back(int val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(bool val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(double val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(int64_t val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(const char *val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(const string &val)
{
	return push_back(JValue(val));
}

bool JValue::push_back(const JValue &jval)
{
	if (E_ARRAY == m_eType || E_NULL == m_eType)
	{
		(*this)[size()] = jval;
		return true;
	}
	return false;
}

bool JValue::push_back(const char *val, size_t len)
{
	return push_back(JValue(val, len));
}

std::string JValue::styleWrite() const
{
	string strDoc;
	return styleWrite(strDoc);
}

const char *JValue::styleWrite(string &strDoc) const
{
	strDoc.clear();
	JWriter jw;
	strDoc = jw.StyleWrite(*this);
	return strDoc.c_str();
}

void JValue::assignDate(time_t val)
{
	Free();
	m_eType = E_DATE;
	m_Value.vDate = val;
}

void JValue::assignData(const char *val, size_t size)
{
	Free();
	m_eType = E_DATA;
	m_Value.vData = new string();
	m_Value.vData->append(val, size);
}

void JValue::assignDateString(time_t val)
{
	Free();
	m_eType = E_STRING;
	m_Value.vString = NewString(JWriter::d2s(val).c_str());
}

time_t JValue::asDate() const
{
	switch (m_eType)
	{
	case E_DATE:
		return m_Value.vDate;
		break;
	case E_STRING:
	{
		if (isDateString())
		{
			tm ft = {0};
			sscanf(m_Value.vString + 5, "%04d-%02d-%02dT%02d:%02d:%02dZ", &ft.tm_year, &ft.tm_mon, &ft.tm_mday, &ft.tm_hour, &ft.tm_min, &ft.tm_sec);
			ft.tm_mon -= 1;
			ft.tm_year -= 1900;
			return mktime(&ft);
		}
	}
	break;
	default:
		break;
	}
	return 0;
}

string JValue::asData() const
{
	switch (m_eType)
	{
	case E_DATA:
		return (NULL == m_Value.vData) ? nullData : *m_Value.vData;
		break;
	case E_STRING:
	{
		if (isDataString())
		{
			ZBase64 b64;
			int nDataLen = 0;
			const char *pdata = b64.Decode(m_Value.vString + 5, 0, &nDataLen);
			string strdata;
			strdata.append(pdata, nDataLen);
			return strdata;
		}
	}
	break;
	default:
		break;
	}

	return nullData;
}

bool JValue::isData() const
{
	return (E_DATA == m_eType);
}

bool JValue::isDate() const
{
	return (E_DATE == m_eType);
}

bool JValue::isDataString() const
{
	if (E_STRING == m_eType)
	{
		if (NULL != m_Value.vString)
		{
			if (strlen(m_Value.vString) >= 5)
			{
				if (0 == memcmp(m_Value.vString, "data:", 5))
				{
					return true;
				}
			}
		}
	}

	return false;
}

bool JValue::isDateString() const
{
	if (E_STRING == m_eType)
	{
		if (NULL != m_Value.vString)
		{
			if (25 == strlen(m_Value.vString))
			{
				if (0 == memcmp(m_Value.vString, "date:", 5))
				{
					const char *pdate = m_Value.vString + 5;
					if ('T' == pdate[10] && 'Z' == pdate[19])
					{
						return true;
					}
				}
			}
		}
	}

	return false;
}

bool JValue::readPList(const string &strdoc, string *pstrerr /*= NULL*/)
{
	return readPList(strdoc.data(), strdoc.size(), pstrerr);
}

bool JValue::readPList(const char *pdoc, size_t len /*= 0*/, string *pstrerr /*= NULL*/)
{
	if (NULL == pdoc)
	{
		return false;
	}

	if (0 == len)
	{
		len = strlen(pdoc);
	}

	PReader reader;
	bool bret = reader.parse(pdoc, len, *this);
	if (!bret)
	{
		if (NULL != pstrerr)
		{
			reader.error(*pstrerr);
		}
	}

	return bret;
}

bool JValue::readFile(const char *file, string *pstrerr /*= NULL*/)
{
	if (NULL != file)
	{
		FILE *fp = fopen(file, "rb");
		if (NULL != fp)
		{
			string strdata;
			struct stat stbuf;
			if (0 == fstat(fileno(fp), &stbuf))
			{
				if (S_ISREG(stbuf.st_mode))
				{
					strdata.reserve(stbuf.st_size);
				}
			}

			char buf[4096] = {0};
			int nread = (int)fread(buf, 1, 4096, fp);
			while (nread > 0)
			{
				strdata.append(buf, nread);
				nread = (int)fread(buf, 1, 4096, fp);
			}
			fclose(fp);
			return read(strdata, pstrerr);
		}
	}

	return false;
}

bool JValue::readPListFile(const char *file, string *pstrerr /*= NULL*/)
{
	if (NULL != file)
	{
		FILE *fp = fopen(file, "rb");
		if (NULL != fp)
		{
			string strdata;
			struct stat stbuf;
			if (0 == fstat(fileno(fp), &stbuf))
			{
				if (S_ISREG(stbuf.st_mode))
				{
					strdata.reserve(stbuf.st_size);
				}
			}

			char buf[4096] = {0};
			int nread = (int)fread(buf, 1, 4096, fp);
			while (nread > 0)
			{
				strdata.append(buf, nread);
				nread = (int)fread(buf, 1, 4096, fp);
			}
			fclose(fp);
			return readPList(strdata, pstrerr);
		}
	}

	return false;
}

bool JValue::WriteDataToFile(const char *file, const char *data, size_t len)
{
	if (NULL == file || NULL == data || len <= 0)
	{
		return false;
	}

	FILE *fp = fopen(file, "wb");
	if (NULL != fp)
	{
		int towrite = (int)len;
		while (towrite > 0)
		{
			int nwrite = (int)fwrite(data + (len - towrite), 1, towrite, fp);
			if (nwrite <= 0)
			{
				break;
			}
			towrite -= nwrite;
		}

		fclose(fp);
		return (towrite > 0) ? false : true;
	}

	return false;
}

bool JValue::writeFile(const char *file)
{
	string strdata;
	write(strdata);
	return WriteDataToFile(file, strdata.data(), strdata.size());
}

bool JValue::writePListFile(const char *file)
{
	string strdata;
	writePList(strdata);
	return WriteDataToFile(file, strdata.data(), strdata.size());
}

bool JValue::styleWriteFile(const char *file)
{
	string strdata;
	styleWrite(strdata);
	return WriteDataToFile(file, strdata.data(), strdata.size());
}

bool JValue::readPath(const char *path, ...)
{
	char file[1024] = {0};
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	return readFile(file);
}

bool JValue::readPListPath(const char *path, ...)
{
	char file[1024] = {0};
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	return readPListFile(file);
}

bool JValue::writePath(const char *path, ...)
{
	char file[1024] = {0};
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	return writeFile(file);
}

bool JValue::writePListPath(const char *path, ...)
{
	char file[1024] = {0};
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	return writePListFile(file);
}

bool JValue::styleWritePath(const char *path, ...)
{
	char file[1024] = {0};
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	return styleWriteFile(file);
}

string JValue::writePList() const
{
	string strDoc;
	return writePList(strDoc);
}

const char *JValue::writePList(string &strDoc) const
{
	strDoc.clear();
	PWriter::FastWrite((*this), strDoc);
	return strDoc.c_str();
}

// Class Reader
// //////////////////////////////////////////////////////////////////
bool JReader::parse(const char *pdoc, JValue &root)
{
	root.clear();
	if (NULL != pdoc)
	{
		m_pBeg = pdoc;
		m_pEnd = m_pBeg + strlen(pdoc);
		m_pCur = m_pBeg;
		m_pErr = m_pBeg;
		m_strErr = "null";
		return readValue(root);
	}
	return false;
}

bool JReader::readValue(JValue &jval)
{
	Token token;
	readToken(token);
	switch (token.type)
	{
	case Token::E_True:
		jval = true;
		break;
	case Token::E_False:
		jval = false;
		break;
	case Token::E_Null:
		jval = JValue();
		break;
	case Token::E_Number:
		return decodeNumber(token, jval);
		break;
	case Token::E_ArrayBegin:
		return readArray(jval);
		break;
	case Token::E_ObjectBegin:
		return readObject(jval);
		break;
	case Token::E_String:
	{
		string strval;
		bool bok = decodeString(token, strval);
		if (bok)
		{
			jval = strval.c_str();
		}
		return bok;
	}
	break;
	default:
		return addError("Syntax error: value, object or array expected.", token.pbeg);
		break;
	}
	return true;
}

bool JReader::readToken(Token &token)
{
	skipSpaces();
	token.pbeg = m_pCur;
	switch (GetNextChar())
	{
	case '{':
		token.type = Token::E_ObjectBegin;
		break;
	case '}':
		token.type = Token::E_ObjectEnd;
		break;
	case '[':
		token.type = Token::E_ArrayBegin;
		break;
	case ']':
		token.type = Token::E_ArrayEnd;
		break;
	case ',':
		token.type = Token::E_ArraySeparator;
		break;
	case ':':
		token.type = Token::E_MemberSeparator;
		break;
	case 0:
		token.type = Token::E_End;
		break;
	case '"':
		token.type = readString() ? Token::E_String : Token::E_Error;
		break;
	case '/':
	case '#':
	case ';':
	{
		skipComment();
		return readToken(token);
	}
	break;
	case '0':
	case '1':
	case '2':
	case '3':
	case '4':
	case '5':
	case '6':
	case '7':
	case '8':
	case '9':
	case '-':
	{
		token.type = Token::E_Number;
		readNumber();
	}
	break;
	case 't':
		token.type = match("rue", 3) ? Token::E_True : Token::E_Error;
		break;
	case 'f':
		token.type = match("alse", 4) ? Token::E_False : Token::E_Error;
		break;
	case 'n':
		token.type = match("ull", 3) ? Token::E_Null : Token::E_Error;
		break;
	default:
		token.type = Token::E_Error;
		break;
	}
	token.pend = m_pCur;
	return true;
}

void JReader::skipSpaces()
{
	while (m_pCur != m_pEnd)
	{
		char c = *m_pCur;
		if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
		{
			m_pCur++;
		}
		else
		{
			break;
		}
	}
}

bool JReader::match(const char *pattern, int patternLength)
{
	if (m_pEnd - m_pCur < patternLength)
	{
		return false;
	}
	int index = patternLength;
	while (index--)
	{
		if (m_pCur[index] != pattern[index])
		{
			return false;
		}
	}
	m_pCur += patternLength;
	return true;
}

void JReader::skipComment()
{
	char c = GetNextChar();
	if (c == '*')
	{
		while (m_pCur != m_pEnd)
		{
			char c = GetNextChar();
			if (c == '*' && *m_pCur == '/')
			{
				break;
			}
		}
	}
	else if (c == '/')
	{
		while (m_pCur != m_pEnd)
		{
			char c = GetNextChar();
			if (c == '\r' || c == '\n')
			{
				break;
			}
		}
	}
}

void JReader::readNumber()
{
	while (m_pCur != m_pEnd)
	{
		char c = *m_pCur;
		if ((c >= '0' && c <= '9') || (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-'))
		{
			++m_pCur;
		}
		else
		{
			break;
		}
	}
}

bool JReader::readString()
{
	char c = 0;
	while (m_pCur != m_pEnd)
	{
		c = GetNextChar();
		if ('\\' == c)
		{
			GetNextChar();
		}
		else if ('"' == c)
		{
			break;
		}
	}
	return ('"' == c);
}

bool JReader::readObject(JValue &jval)
{
	string name;
	Token tokenName;
	jval = JValue(JValue::E_OBJECT);
	while (readToken(tokenName))
	{
		if (Token::E_ObjectEnd == tokenName.type)
		{ //empty
			return true;
		}

		if (Token::E_String != tokenName.type)
		{
			break;
		}

		if (!decodeString(tokenName, name))
		{
			return false;
		}

		Token colon;
		readToken(colon);
		if (Token::E_MemberSeparator != colon.type)
		{
			return addError("Missing ':' after object member name", colon.pbeg);
		}

		if (!readValue(jval[name.c_str()]))
		{ // error already set
			return false;
		}

		Token comma;
		readToken(comma);
		if (Token::E_ObjectEnd == comma.type)
		{
			return true;
		}

		if (Token::E_ArraySeparator != comma.type)
		{
			return addError("Missing ',' or '}' in object declaration", comma.pbeg);
		}
	}
	return addError("Missing '}' or object member name", tokenName.pbeg);
}

bool JReader::readArray(JValue &jval)
{
	jval = JValue(JValue::E_ARRAY);
	skipSpaces();
	if (']' == *m_pCur) // empty array
	{
		Token endArray;
		readToken(endArray);
		return true;
	}

	size_t index = 0;
	while (true)
	{
		if (!readValue(jval[index++]))
		{ //error already set
			return false;
		}

		Token token;
		readToken(token);
		if (Token::E_ArrayEnd == token.type)
		{
			break;
		}
		if (Token::E_ArraySeparator != token.type)
		{
			return addError("Missing ',' or ']' in array declaration", token.pbeg);
		}
	}
	return true;
}

bool JReader::decodeNumber(Token &token, JValue &jval)
{
	int64_t val = 0;
	bool isNeg = false;
	const char *pcur = token.pbeg;
	if ('-' == *pcur)
	{
		pcur++;
		isNeg = true;
	}
	for (const char *p = pcur; p != token.pend; p++)
	{
		char c = *p;
		if ('.' == c || 'e' == c || 'E' == c)
		{
			return decodeDouble(token, jval);
		}
		else if (c < '0' || c > '9')
		{
			return addError("'" + string(token.pbeg, token.pend) + "' is not a number.", token.pbeg);
		}
		else
		{
			val = val * 10 + (c - '0');
		}
	}
	jval = isNeg ? -val : val;
	return true;
}

bool JReader::decodeDouble(Token &token, JValue &jval)
{
	const size_t szbuf = 512;
	size_t len = size_t(token.pend - token.pbeg);
	if (len <= szbuf)
	{
		char buf[szbuf];
		memcpy(buf, token.pbeg, len);
		buf[len] = 0;
		double val = 0;
		if (1 == sscanf(buf, "%lf", &val))
		{
			jval = val;
			return true;
		}
	}
	return addError("'" + string(token.pbeg, token.pend) + "' is too large or not a number.", token.pbeg);
}

bool JReader::decodeString(Token &token, string &strdec)
{
	strdec = "";
	const char *pcur = token.pbeg + 1;
	const char *pend = token.pend - 1;
	strdec.reserve(size_t(token.pend - token.pbeg));
	while (pcur != pend)
	{
		char c = *pcur++;
		if ('\\' == c)
		{
			if (pcur != pend)
			{
				char escape = *pcur++;
				switch (escape)
				{
				case '"':
					strdec += '"';
					break;
				case '\\':
					strdec += '\\';
					break;
				case 'b':
					strdec += '\b';
					break;
				case 'f':
					strdec += '\f';
					break;
				case 'n':
					strdec += '\n';
					break;
				case 'r':
					strdec += '\r';
					break;
				case 't':
					strdec += '\t';
					break;
				case '/':
					strdec += '/';
					break;
				case 'u':
				{ // based on description from http://en.wikipedia.org/wiki/UTF-8

					string strUnic;
					strUnic.append(pcur, 4);

					pcur += 4;

					unsigned int cp = 0;
					if (1 != sscanf(strUnic.c_str(), "%x", &cp))
					{
						return addError("Bad escape sequence in string", pcur);
					}

					string strUTF8;

					if (cp <= 0x7f)
					{
						strUTF8.resize(1);
						strUTF8[0] = static_cast<char>(cp);
					}
					else if (cp <= 0x7FF)
					{
						strUTF8.resize(2);
						strUTF8[1] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[0] = static_cast<char>(0xC0 | (0x1f & (cp >> 6)));
					}
					else if (cp <= 0xFFFF)
					{
						strUTF8.resize(3);
						strUTF8[2] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[1] = 0x80 | static_cast<char>((0x3f & (cp >> 6)));
						strUTF8[0] = 0xE0 | static_cast<char>((0xf & (cp >> 12)));
					}
					else if (cp <= 0x10FFFF)
					{
						strUTF8.resize(4);
						strUTF8[3] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[2] = static_cast<char>(0x80 | (0x3f & (cp >> 6)));
						strUTF8[1] = static_cast<char>(0x80 | (0x3f & (cp >> 12)));
						strUTF8[0] = static_cast<char>(0xF0 | (0x7 & (cp >> 18)));
					}

					strdec += strUTF8;
				}
				break;
				default:
					return addError("Bad escape sequence in string", pcur);
					break;
				}
			}
			else
			{
				return addError("Empty escape sequence in string", pcur);
			}
		}
		else if ('"' == c)
		{
			break;
		}
		else
		{
			strdec += c;
		}
	}
	return true;
}

bool JReader::addError(const string &message, const char *ploc)
{
	m_pErr = ploc;
	m_strErr = message;
	return false;
}

char JReader::GetNextChar()
{
	return (m_pCur == m_pEnd) ? 0 : *m_pCur++;
}

void JReader::error(string &strmsg) const
{
	strmsg = "";
	int row = 1;
	const char *pcur = m_pBeg;
	const char *plast = m_pBeg;
	while (pcur < m_pErr && pcur <= m_pEnd)
	{
		char c = *pcur++;
		if (c == '\r' || c == '\n')
		{
			if (c == '\r' && *pcur == '\n')
			{
				pcur++;
			}
			row++;
			plast = pcur;
		}
	}
	char msg[64];
	sprintf(msg, "Error: Line %d, Column %d, ", row, int(m_pErr - plast) + 1);
	strmsg += msg + m_strErr + "\n";
}

// Class Writer
// //////////////////////////////////////////////////////////////////
void JWriter::FastWrite(const JValue &jval, string &strDoc)
{
	strDoc = "";
	FastWriteValue(jval, strDoc);
	//strDoc += "\n";
}

void JWriter::FastWriteValue(const JValue &jval, string &strDoc)
{
	switch (jval.type())
	{
	case JValue::E_NULL:
		strDoc += "null";
		break;
	case JValue::E_INT:
		strDoc += v2s(jval.asInt64());
		break;
	case JValue::E_BOOL:
		strDoc += jval.asBool() ? "true" : "false";
		break;
	case JValue::E_FLOAT:
		strDoc += v2s(jval.asFloat());
		break;
	case JValue::E_STRING:
		strDoc += v2s(jval.asCString());
		break;
	case JValue::E_ARRAY:
	{
		strDoc += "[";
		size_t usize = jval.size();
		for (size_t i = 0; i < usize; i++)
		{
			strDoc += (i > 0) ? "," : "";
			FastWriteValue(jval[i], strDoc);
		}
		strDoc += "]";
	}
	break;
	case JValue::E_OBJECT:
	{
		strDoc += "{";
		vector<string> arrKeys;
		jval.keys(arrKeys);
		size_t usize = arrKeys.size();
		for (size_t i = 0; i < usize; i++)
		{
			const string &name = arrKeys[i];
			strDoc += (i > 0) ? "," : "";
			strDoc += v2s(name.c_str()) + ":";
			FastWriteValue(jval[name.c_str()], strDoc);
		}
		strDoc += "}";
	}
	break;
	case JValue::E_DATE:
	{
		strDoc += "\"date:";
		strDoc += d2s(jval.asDate());
		strDoc += "\"";
	}
	break;
	case JValue::E_DATA:
	{
		strDoc += "\"data:";
		const string &strData = jval.asData();
		ZBase64 b64;
		strDoc += b64.Encode(strData.data(), (int)strData.size());
		strDoc += "\"";
	}
	break;
	}
}

const string &JWriter::StyleWrite(const JValue &jval)
{
	m_strDoc = "";
	m_strTab = "";
	m_bAddChild = false;
	StyleWriteValue(jval);
	m_strDoc += "\n";
	return m_strDoc;
}

void JWriter::StyleWriteValue(const JValue &jval)
{
	switch (jval.type())
	{
	case JValue::E_NULL:
		PushValue("null");
		break;
	case JValue::E_INT:
		PushValue(v2s(jval.asInt64()));
		break;
	case JValue::E_BOOL:
		PushValue(jval.asBool() ? "true" : "false");
		break;
	case JValue::E_FLOAT:
		PushValue(v2s(jval.asFloat()));
		break;
	case JValue::E_STRING:
		PushValue(v2s(jval.asCString()));
		break;
	case JValue::E_ARRAY:
		StyleWriteArrayValue(jval);
		break;
	case JValue::E_OBJECT:
	{
		vector<string> arrKeys;
		jval.keys(arrKeys);
		if (!arrKeys.empty())
		{
			m_strDoc += '\n' + m_strTab + "{";
			m_strTab += '\t';
			size_t usize = arrKeys.size();
			for (size_t i = 0; i < usize; i++)
			{
				const string &name = arrKeys[i];
				m_strDoc += (i > 0) ? "," : "";
				m_strDoc += '\n' + m_strTab + v2s(name.c_str()) + " : ";
				StyleWriteValue(jval[name]);
			}
			m_strTab.resize(m_strTab.size() - 1);
			m_strDoc += '\n' + m_strTab + "}";
		}
		else
		{
			PushValue("{}");
		}
	}
	break;
	case JValue::E_DATE:
	{
		string strDoc;
		strDoc += "\"date:";
		strDoc += d2s(jval.asDate());
		strDoc += "\"";
		PushValue(strDoc);
	}
	break;
	case JValue::E_DATA:
	{
		string strDoc;
		strDoc += "\"data:";
		const string &strData = jval.asData();
		ZBase64 b64;
		strDoc += b64.Encode(strData.data(), (int)strData.size());
		strDoc += "\"";
		PushValue(strDoc);
	}
	break;
	}
}

void JWriter::StyleWriteArrayValue(const JValue &jval)
{
	size_t usize = jval.size();
	if (usize > 0)
	{
		bool isArrayMultiLine = isMultineArray(jval);
		if (isArrayMultiLine)
		{
			m_strDoc += '\n' + m_strTab + "[";
			m_strTab += '\t';
			bool hasChildValue = !m_childValues.empty();
			for (size_t i = 0; i < usize; i++)
			{
				m_strDoc += (i > 0) ? "," : "";
				if (hasChildValue)
				{
					m_strDoc += '\n' + m_strTab + m_childValues[i];
				}
				else
				{
					m_strDoc += '\n' + m_strTab;
					StyleWriteValue(jval[i]);
				}
			}
			m_strTab.resize(m_strTab.size() - 1);
			m_strDoc += '\n' + m_strTab + "]";
		}
		else
		{
			m_strDoc += "[ ";
			for (size_t i = 0; i < usize; ++i)
			{
				m_strDoc += (i > 0) ? ", " : "";
				m_strDoc += m_childValues[i];
			}
			m_strDoc += " ]";
		}
	}
	else
	{
		PushValue("[]");
	}
}

bool JWriter::isMultineArray(const JValue &jval)
{
	m_childValues.clear();
	size_t usize = jval.size();
	bool isMultiLine = (usize >= 25);
	if (!isMultiLine)
	{
		for (size_t i = 0; i < usize; i++)
		{
			if (jval[i].size() > 0)
			{
				isMultiLine = true;
				break;
			}
		}
	}
	if (!isMultiLine)
	{
		m_bAddChild = true;
		m_childValues.reserve(usize);
		size_t lineLength = 4 + (usize - 1) * 2; // '[ ' + ', '*n + ' ]'
		for (size_t i = 0; i < usize; i++)
		{
			StyleWriteValue(jval[i]);
			lineLength += m_childValues[i].length();
		}
		m_bAddChild = false;
		isMultiLine = lineLength >= 75;
	}
	return isMultiLine;
}

void JWriter::PushValue(const string &strval)
{
	if (!m_bAddChild)
	{
		m_strDoc += strval;
	}
	else
	{
		m_childValues.push_back(strval);
	}
}

string JWriter::v2s(int64_t val)
{
	char buf[32];
	sprintf(buf, "%" PRId64, val);
	return buf;
}

string JWriter::v2s(double val)
{
	char buf[512];
	sprintf(buf, "%g", val);
	return buf;
}

string JWriter::d2s(time_t t)
{
	//t = (t > 0x7933F8EFF) ? (0x7933F8EFF - 1) : t;

	tm ft = {0};

#ifdef _WIN32
	localtime_s(&ft, &t);
#else
	localtime_r(&t, &ft);
#endif

	ft.tm_year = (ft.tm_year < 0) ? 0 : ft.tm_year;
	ft.tm_mon = (ft.tm_mon < 0) ? 0 : ft.tm_mon;
	ft.tm_mday = (ft.tm_mday < 0) ? 0 : ft.tm_mday;
	ft.tm_hour = (ft.tm_hour < 0) ? 0 : ft.tm_hour;
	ft.tm_min = (ft.tm_min < 0) ? 0 : ft.tm_min;
	ft.tm_sec = (ft.tm_sec < 0) ? 0 : ft.tm_sec;

	char szDate[64] = {0};
	sprintf(szDate, "%04d-%02d-%02dT%02d:%02d:%02dZ", ft.tm_year + 1900, ft.tm_mon + 1, ft.tm_mday, ft.tm_hour, ft.tm_min, ft.tm_sec);
	return szDate;
}

string JWriter::v2s(const char *pstr)
{
	if (NULL != strpbrk(pstr, "\"\\\b\f\n\r\t"))
	{
		string ret;
		ret.reserve(strlen(pstr) * 2 + 3);
		ret += "\"";
		for (const char *c = pstr; 0 != *c; c++)
		{
			switch (*c)
			{
			case '\\':
			{
				c++;
				bool bUnicode = false;
				if ('u' == *c)
				{
					bool bFlag = true;
					for (int i = 1; i <= 4; i++)
					{
						if (!isdigit(*(c + i)))
						{
							bFlag = false;
							break;
						}
					}
					bUnicode = bFlag;
				}

				if (true == bUnicode)
				{
					ret += "\\u";
				}
				else
				{
					ret += "\\\\";
					c--;
				}
			}
			break;
			case '\"':
				ret += "\\\"";
				break;
			case '\b':
				ret += "\\b";
				break;
			case '\f':
				ret += "\\f";
				break;
			case '\n':
				ret += "\\n";
				break;
			case '\r':
				ret += "\\r";
				break;
			case '\t':
				ret += "\\t";
				break;
			default:
				ret += *c;
				break;
			}
		}
		ret += "\"";
		return ret;
	}
	else
	{
		return string("\"") + pstr + "\"";
	}
}

std::string JWriter::vstring2s(const char *pstr)
{
	return string("\\\"") + pstr + "\\\"";
}

//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////

#define BE16TOH(x) ((((x)&0xFF00) >> 8) | (((x)&0x00FF) << 8))

#define BE32TOH(x) ((((x)&0xFF000000) >> 24) | (((x)&0x00FF0000) >> 8) | (((x)&0x0000FF00) << 8) | (((x)&0x000000FF) << 24))

#define BE64TOH(x) ((((x)&0xFF00000000000000ull) >> 56) | (((x)&0x00FF000000000000ull) >> 40) | (((x)&0x0000FF0000000000ull) >> 24) | (((x)&0x000000FF00000000ull) >> 8) | (((x)&0x00000000FF000000ull) << 8) | (((x)&0x0000000000FF0000ull) << 24) | (((x)&0x000000000000FF00ull) << 40) | (((x)&0x00000000000000FFull) << 56))

//////////////////////////////////////////////////////////////////////////
PReader::PReader()
{
	//xml
	m_pBeg = NULL;
	m_pEnd = NULL;
	m_pCur = NULL;
	m_pErr = NULL;

	//binary
	m_pTrailer = NULL;
	m_uObjects = 0;
	m_uOffsetSize = 0;
	m_pOffsetTable = 0;
	m_uDictParamSize = 0;
}

bool PReader::parse(const char *pdoc, size_t len, JValue &root)
{
	root.clear();
	if (NULL == pdoc)
	{
		return false;
	}

	if (len < 30)
	{
		return false;
	}

	if (0 == memcmp(pdoc, "bplist00", 8))
	{
		return parseBinary(pdoc, len, root);
	}
	else
	{
		m_pBeg = pdoc;
		m_pEnd = m_pBeg + len;
		m_pCur = m_pBeg;
		m_pErr = m_pBeg;
		m_strErr = "null";

		Token token;
		readToken(token);
		return readValue(root, token);
	}
}

bool PReader::readValue(JValue &pval, Token &token)
{
	switch (token.type)
	{
	case Token::E_True:
		pval = true;
		break;
	case Token::E_False:
		pval = false;
		break;
	case Token::E_Null:
		pval = JValue();
		break;
	case Token::E_Integer:
		return decodeNumber(token, pval);
		break;
	case Token::E_Real:
		return decodeDouble(token, pval);
		break;
	case Token::E_ArrayNull:
		pval = JValue(JValue::E_ARRAY);
		break;
	case Token::E_ArrayBegin:
		return readArray(pval);
		break;
	case Token::E_DictionaryNull:
		pval = JValue(JValue::E_OBJECT);
		break;
	case Token::E_DictionaryBegin:
		return readDictionary(pval);
		break;
	case Token::E_Date:
	{
		string strval;
		decodeString(token, strval);

		tm ft = {0};
		sscanf(strval.c_str(), "%04d-%02d-%02dT%02d:%02d:%02dZ", &ft.tm_year, &ft.tm_mon, &ft.tm_mday, &ft.tm_hour, &ft.tm_min, &ft.tm_sec);
		ft.tm_mon -= 1;
		ft.tm_year -= 1900;
		pval.assignDate(mktime(&ft));
	}
	break;
	case Token::E_Data:
	{
		string strval;
		decodeString(token, strval);

		ZBase64 b64;
		int nDecLen = 0;
		const char *data = b64.Decode(strval.data(), (int)strval.size(), &nDecLen);
		pval.assignData(data, nDecLen);
	}
	break;
	case Token::E_String:
	{
		string strval;
		decodeString(token, strval, false);
		XMLUnescape(strval);
		pval = strval.c_str();
	}
	break;
	default:
		return addError("Syntax error: value, dictionary or array expected.", token.pbeg);
		break;
	}
	return true;
}

bool PReader::readLabel(string &label)
{
	skipSpaces();

	char c = *m_pCur++;
	if ('<' != c)
	{
		return false;
	}

	label.clear();
	label.reserve(10);
	label += c;

	bool bEnd = false;
	while (m_pCur != m_pEnd)
	{
		c = *m_pCur++;
		if ('>' == c)
		{
			if ('/' == *(m_pCur - 1) || '?' == *(m_pCur - 1))
			{
				label += *(m_pCur - 1);
			}

			label += c;
			break;
		}
		else if (' ' == c)
		{
			bEnd = true;
		}
		else if (!bEnd)
		{
			label += c;
		}
	}

	if ('>' != c)
	{
		label.clear();
		return false;
	}

	return (!label.empty());
}

void PReader::endLabel(Token &token, const char *szLabel)
{
	string label;
	readLabel(label);
	if (szLabel != label)
	{
		token.type = Token::E_Error;
	}
}

bool PReader::readToken(Token &token)
{
	string label;
	if (!readLabel(label))
	{
		token.type = Token::E_Error;
		return false;
	}

	if ('?' == label.at(1) || '!' == label.at(1))
	{
		return readToken(token);
	}

	if ("<dict>" == label)
	{
		token.type = Token::E_DictionaryBegin;
	}
	else if ("</dict>" == label)
	{
		token.type = Token::E_DictionaryEnd;
	}
	else if ("<array>" == label)
	{
		token.type = Token::E_ArrayBegin;
	}
	else if ("</array>" == label)
	{
		token.type = Token::E_ArrayEnd;
	}
	else if ("<key>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readString() ? Token::E_Key : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</key>");
	}
	else if ("<key/>" == label)
	{
		token.type = Token::E_Key;
	}
	else if ("<string>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readString() ? Token::E_String : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</string>");
	}
	else if ("<date>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readString() ? Token::E_Date : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</date>");
	}
	else if ("<data>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readString() ? Token::E_Data : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</data>");
	}
	else if ("<integer>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readNumber() ? Token::E_Integer : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</integer>");
	}
	else if ("<real>" == label)
	{
		token.pbeg = m_pCur;
		token.type = readNumber() ? Token::E_Real : Token::E_Error;
		token.pend = m_pCur;

		endLabel(token, "</real>");
	}
	else if ("<true/>" == label)
	{
		token.type = Token::E_True;
	}
	else if ("<false/>" == label)
	{
		token.type = Token::E_False;
	}
	else if ("<array/>" == label)
	{
		token.type = Token::E_ArrayNull;
	}
	else if ("<dict/>" == label)
	{
		token.type = Token::E_DictionaryNull;
	}
	else if ("<data/>" == label || "<date/>" == label || "<string/>" == label || "<integer/>" == label || "<real/>" == label)
	{
		token.type = Token::E_Null;
	}
	else if ("<plist>" == label)
	{
		return readToken(token);
	}
	else if ("</plist>" == label || "<plist/>" == label)
	{
		token.type = Token::E_End;
	}
	else
	{
		token.type = Token::E_Error;
	}

	return true;
}

void PReader::skipSpaces()
{
	while (m_pCur != m_pEnd)
	{
		char c = *m_pCur;
		if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
		{
			m_pCur++;
		}
		else
		{
			break;
		}
	}
}

bool PReader::readNumber()
{
	while (m_pCur != m_pEnd)
	{
		char c = *m_pCur;
		if ((c >= '0' && c <= '9') || (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-'))
		{
			++m_pCur;
		}
		else
		{
			break;
		}
	}
	return true;
}

bool PReader::readString()
{
	while (m_pCur != m_pEnd)
	{
		if ('<' == *m_pCur)
		{
			break;
		}
		m_pCur++;
	}
	return ('<' == *m_pCur);
}

bool PReader::readDictionary(JValue &pval)
{
	Token key;
	string strKey;
	pval = JValue(JValue::E_OBJECT);
	while (readToken(key))
	{
		if (Token::E_DictionaryEnd == key.type)
		{ //empty
			return true;
		}

		if (Token::E_Key != key.type)
		{
			break;
		}

		strKey = "";
		if (!decodeString(key, strKey))
		{
			return false;
		}
		XMLUnescape(strKey);

		Token val;
		readToken(val);
		if (!readValue(pval[strKey.c_str()], val))
		{
			return false;
		}
	}
	return addError("Missing '</dict>' or dictionary member name", key.pbeg);
}

bool PReader::readArray(JValue &pval)
{
	pval = JValue(JValue::E_ARRAY);

	size_t index = 0;
	while (true)
	{
		Token token;
		readToken(token);
		if (Token::E_ArrayEnd == token.type)
		{
			return true;
		}

		if (!readValue(pval[index++], token))
		{
			return false;
		}
	}

	return true;
}

bool PReader::decodeNumber(Token &token, JValue &pval)
{
	int64_t val = 0;
	bool isNeg = false;
	const char *pcur = token.pbeg;
	if ('-' == *pcur)
	{
		pcur++;
		isNeg = true;
	}
	for (const char *p = pcur; p != token.pend; p++)
	{
		char c = *p;
		if ('.' == c || 'e' == c || 'E' == c)
		{
			return decodeDouble(token, pval);
		}
		else if (c < '0' || c > '9')
		{
			return addError("'" + string(token.pbeg, token.pend) + "' is not a number.", token.pbeg);
		}
		else
		{
			val = val * 10 + (c - '0');
		}
	}
	pval = isNeg ? -val : val;
	return true;
}

bool PReader::decodeDouble(Token &token, JValue &pval)
{
	const size_t szbuf = 512;
	size_t len = size_t(token.pend - token.pbeg);
	if (len <= szbuf)
	{
		char buf[szbuf];
		memcpy(buf, token.pbeg, len);
		buf[len] = 0;
		double val = 0;
		if (1 == sscanf(buf, "%lf", &val))
		{
			pval = val;
			return true;
		}
	}
	return addError("'" + string(token.pbeg, token.pend) + "' is too large or not a number.", token.pbeg);
}

bool PReader::decodeString(Token &token, string &strdec, bool filter)
{
	const char *pcur = token.pbeg;
	const char *pend = token.pend;
	strdec.reserve(size_t(token.pend - token.pbeg) + 6);
	while (pcur != pend)
	{
		char c = *pcur++;
		if (filter && ('\n' == c || '\r' == c || '\t' == c)) 
		{
			continue;
		}
		strdec += c;
	}
	return true;
}

bool PReader::addError(const string &message, const char *ploc)
{
	m_pErr = ploc;
	m_strErr = message;
	return false;
}

void PReader::error(string &strmsg) const
{
	strmsg = "";
	int row = 1;
	const char *pcur = m_pBeg;
	const char *plast = m_pBeg;
	while (pcur < m_pErr && pcur <= m_pEnd)
	{
		char c = *pcur++;
		if (c == '\r' || c == '\n')
		{
			if (c == '\r' && *pcur == '\n')
			{
				pcur++;
			}
			row++;
			plast = pcur;
		}
	}
	char msg[64];
	sprintf(msg, "Error: Line %d, Column %d, ", row, int(m_pErr - plast) + 1);
	strmsg += msg + m_strErr + "\n";
}

//////////////////////////////////////////////////////////////////////////
uint32_t PReader::getUInt24FromBE(const char *v)
{
	uint32_t ret = 0;
	uint8_t *tmp = (uint8_t *)&ret;
	memcpy(tmp, v, 3 * sizeof(char));
	byteConvert(tmp, sizeof(uint32_t));
	return ret;
}

uint64_t PReader::getUIntVal(const char *v, size_t size)
{
	if (8 == size)
		return BE64TOH(*((uint64_t *)v));
	else if (4 == size)
		return BE32TOH(*((uint32_t *)v));
	else if (3 == size)
		return getUInt24FromBE(v);
	else if (2 == size)
		return BE16TOH(*((uint16_t *)v));
	else
		return *((uint8_t *)v);
}

void PReader::byteConvert(uint8_t *v, size_t size)
{
	uint8_t tmp = 0;
	for (size_t i = 0, j = 0; i < (size / 2); i++)
	{
		tmp = v[i];
		j = (size - 1) - i;
		v[i] = v[j];
		v[j] = tmp;
	}
}

bool PReader::readUIntSize(const char *&pcur, size_t &size)
{
	JValue temp;
	readBinaryValue(pcur, temp);
	if (temp.isInt())
	{
		size = (size_t)temp.asInt64();
		return true;
	}

	assert(0);
	return false;
}

bool PReader::readUnicode(const char *pcur, size_t size, JValue &pv)
{
	if (0 == size)
	{
		pv = "";
		return false;
	}

	uint16_t *unistr = (uint16_t *)malloc(2 * size);
	memcpy(unistr, pcur, 2 * size);
	for (size_t i = 0; i < size; i++)
	{
		byteConvert((uint8_t *)(unistr + i), 2);
	}

	char *outbuf = (char *)malloc(3 * (size + 1));

	size_t p = 0;
	size_t i = 0;
	uint16_t wc = 0;
	while (i < size)
	{
		wc = unistr[i++];
		if (wc >= 0x800)
		{
			outbuf[p++] = (char)(0xE0 + ((wc >> 12) & 0xF));
			outbuf[p++] = (char)(0x80 + ((wc >> 6) & 0x3F));
			outbuf[p++] = (char)(0x80 + (wc & 0x3F));
		}
		else if (wc >= 0x80)
		{
			outbuf[p++] = (char)(0xC0 + ((wc >> 6) & 0x1F));
			outbuf[p++] = (char)(0x80 + (wc & 0x3F));
		}
		else
		{
			outbuf[p++] = (char)(wc & 0x7F);
		}
	}

	outbuf[p] = 0;

	pv = outbuf;

	free(outbuf);
	outbuf = NULL;
	free(unistr);
	unistr = NULL;

	return true;
}

bool PReader::readBinaryValue(const char *&pcur, JValue &pv)
{
	enum
	{
		BPLIST_NULL = 0x00,
		BPLIST_FALSE = 0x08,
		BPLIST_TRUE = 0x09,
		BPLIST_FILL = 0x0F,
		BPLIST_UINT = 0x10,
		BPLIST_REAL = 0x20,
		BPLIST_DATE = 0x30,
		BPLIST_DATA = 0x40,
		BPLIST_STRING = 0x50,
		BPLIST_UNICODE = 0x60,
		BPLIST_UNK_0x70 = 0x70,
		BPLIST_UID = 0x80,
		BPLIST_ARRAY = 0xA0,
		BPLIST_SET = 0xC0,
		BPLIST_DICT = 0xD0,
		BPLIST_MASK = 0xF0
	};

	uint8_t c = *pcur++;
	uint8_t key = c & 0xF0;
	uint8_t val = c & 0x0F;

	switch (key)
	{
	case BPLIST_NULL:
	{
		switch (val)
		{
		case BPLIST_TRUE:
		{
			pv = true;
		}
		break;
		case BPLIST_FALSE:
		{
			pv = false;
		}
		break;
		case BPLIST_NULL:
		{
		}
		break;
		default:
		{
			assert(0);
			return false;
		}
		break;
		}
	}
	break;
	case BPLIST_UID:
	case BPLIST_UINT:
	{
		size_t size = 1 << val;
		switch (size)
		{
		case sizeof(uint8_t):
		case sizeof(uint16_t):
		case sizeof(uint32_t):
		case sizeof(uint64_t):
		{
			pv = (int64_t)getUIntVal(pcur, size);
		}
		break;
		default:
		{
			assert(0);
			return false;
		}
		break;
		};

		pcur += size;
	}
	break;
	case BPLIST_REAL:
	{
		size_t size = 1 << val;

		uint8_t *buf = (uint8_t *)malloc(size);
		memcpy(buf, pcur, size);
		byteConvert(buf, size);

		switch (size)
		{
		case sizeof(float):
			pv = (double)(*(float *)buf);
		case sizeof(double):
			pv = (*(double *)buf);
			break;
		default:
		{
			assert(0);
			free(buf);
			return false;
		}
		break;
		}

		free(buf);
	}
	break;

	case BPLIST_DATE:
	{
		if (3 == val)
		{
			size_t size = 1 << val;
			uint8_t *buf = (uint8_t *)malloc(size);
			memcpy(buf, pcur, size);
			byteConvert(buf, size);
			pv.assignDate(((time_t)(*(double *)buf)) + 978278400);
			free(buf);
		}
		else
		{
			assert(0);
			return false;
		}
	}
	break;

	case BPLIST_DATA:
	{
		size_t size = val;
		if (0x0F == val)
		{
			if (!readUIntSize(pcur, size))
			{
				return false;
			}
		}
		pv.assignData(pcur, size);
	}
	break;

	case BPLIST_STRING:
	{
		size_t size = val;
		if (0x0F == val)
		{
			if (!readUIntSize(pcur, size))
			{
				return false;
			}
		}

		string strval;
		strval.append(pcur, size);
		strval.append(1, 0);
		pv = strval.c_str();
	}
	break;

	case BPLIST_UNICODE:
	{
		size_t size = val;
		if (0x0F == val)
		{
			if (!readUIntSize(pcur, size))
			{
				return false;
			}
		}

		readUnicode(pcur, size, pv);
	}
	break;
	case BPLIST_ARRAY:
	case BPLIST_UNK_0x70:
	{
		size_t size = val;
		if (0x0F == val)
		{
			if (!readUIntSize(pcur, size))
			{
				return false;
			}
		}

		for (size_t i = 0; i < size; i++)
		{
			uint64_t uIndex = getUIntVal((const char *)pcur + i * m_uDictParamSize, m_uDictParamSize);
			if (uIndex < m_uObjects)
			{
				const char *pval = (m_pBeg + getUIntVal(m_pOffsetTable + uIndex * m_uOffsetSize, m_uOffsetSize));
				readBinaryValue(pval, pv[i]);
			}
			else
			{
				assert(0);
				return false;
			}
		}
	}
	break;

	case BPLIST_SET:
	case BPLIST_DICT:
	{
		size_t size = val;
		if (0x0F == val)
		{
			if (!readUIntSize(pcur, size))
			{
				return false;
			}
		}

		for (size_t i = 0; i < size; i++)
		{
			JValue pvKey;
			JValue pvVal;

			uint64_t uKeyIndex = getUIntVal((const char *)pcur + i * m_uDictParamSize, m_uDictParamSize);
			uint64_t uValIndex = getUIntVal((const char *)pcur + (i + size) * m_uDictParamSize, m_uDictParamSize);

			if (uKeyIndex < m_uObjects)
			{
				const char *pval = (m_pBeg + getUIntVal(m_pOffsetTable + uKeyIndex * m_uOffsetSize, m_uOffsetSize));
				readBinaryValue(pval, pvKey);
			}

			if (uValIndex < m_uObjects)
			{
				const char *pval = (m_pBeg + getUIntVal(m_pOffsetTable + uValIndex * m_uOffsetSize, m_uOffsetSize));
				readBinaryValue(pval, pvVal);
			}

			if (pvKey.isString() && !pvVal.isNull())
			{
				pv[pvKey.asCString()] = pvVal;
			}
		}
	}
	break;
	default:
	{
		assert(0);
		return false;
	}
	}

	return true;
}

bool PReader::parseBinary(const char *pbdoc, size_t len, JValue &pv)
{
	m_pBeg = pbdoc;

	m_pTrailer = m_pBeg + len - 26;

	m_uOffsetSize = m_pTrailer[0];
	m_uDictParamSize = m_pTrailer[1];
	m_uObjects = getUIntVal(m_pTrailer + 2, 8);

	if (0 == m_uObjects)
	{
		return false;
	}

	m_pOffsetTable = m_pBeg + getUIntVal(m_pTrailer + 18, 8);
	const char *pval = (m_pBeg + getUIntVal(m_pOffsetTable, m_uOffsetSize));
	return readBinaryValue(pval, pv);
}

void PReader::XMLUnescape(string &strval)
{
	PWriter::StringReplace(strval, "&amp;", "&");
	PWriter::StringReplace(strval, "&lt;", "<");
	//PWriter::StringReplace(strval,"&gt;", ">");		//optional
	//PWriter::StringReplace(strval, "&apos;", "'");	//optional
	//PWriter::StringReplace(strval, "&quot;", "\"");	//optional
}

//////////////////////////////////////////////////////////////////////////
void PWriter::FastWrite(const JValue &pval, string &strdoc)
{
	strdoc.clear();
	strdoc = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
			 "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
			 "<plist version=\"1.0\">\n";

	string strindent;
	FastWriteValue(pval, strdoc, strindent);

	strdoc += "</plist>";
}

void PWriter::FastWriteValue(const JValue &pval, string &strdoc, string &strindent)
{
	if (pval.isObject())
	{
		strdoc += strindent;
		if (pval.isEmpty())
		{
			strdoc += "<dict/>\n";
			return;
		}
		strdoc += "<dict>\n";
		vector<string> arrKeys;
		if (pval.keys(arrKeys))
		{
			strindent.push_back('\t');
			for (size_t i = 0; i < arrKeys.size(); i++)
			{
				if (!pval[arrKeys[i].c_str()].isNull())
				{
					string strkey = arrKeys[i];
					XMLEscape(strkey);
					strdoc += strindent;
					strdoc += "<key>";
					strdoc += strkey;
					strdoc += "</key>\n";
					FastWriteValue(pval[arrKeys[i].c_str()], strdoc, strindent);
				}
			}
			strindent.erase(strindent.end() - 1);
		}
		strdoc += strindent;
		strdoc += "</dict>\n";
	}
	else if (pval.isArray())
	{
		strdoc += strindent;
		if (pval.isEmpty())
		{
			strdoc += "<array/>\n";
			return;
		}
		strdoc += "<array>\n";
		strindent.push_back('\t');
		for (size_t i = 0; i < pval.size(); i++)
		{
			FastWriteValue(pval[i], strdoc, strindent);
		}
		strindent.erase(strindent.end() - 1);
		strdoc += strindent;
		strdoc += "</array>\n";
	}
	else if (pval.isDate())
	{
		strdoc += strindent;
		strdoc += "<date>";
		strdoc += JWriter::d2s(pval.asDate());
		strdoc += "</date>\n";
	}
	else if (pval.isData())
	{
		ZBase64 b64;
		string strdata = pval.asData();
		strdoc += strindent;
		strdoc += "<data>\n";
		strdoc += strindent;
		strdoc += b64.Encode(strdata.data(), (int)strdata.size());
		strdoc += "\n";
		strdoc += strindent;
		strdoc += "</data>\n";
	}
	else if (pval.isString())
	{
		strdoc += strindent;
		if (pval.isDateString())
		{
			strdoc += "<date>";
			strdoc += pval.asString().c_str() + 5;
			strdoc += "</date>\n";
		}
		else if (pval.isDataString())
		{
			strdoc += "<data>\n";
			strdoc += strindent;
			strdoc += pval.asString().c_str() + 5;
			strdoc += "\n";
			strdoc += strindent;
			strdoc += "</data>\n";
		}
		else
		{
			string strval = pval.asCString();
			XMLEscape(strval);
			strdoc += "<string>";
			strdoc += strval;
			strdoc += "</string>\n";
		}
	}
	else if (pval.isBool())
	{
		strdoc += strindent;
		strdoc += (pval.asBool() ? "<true/>\n" : "<false/>\n");
	}
	else if (pval.isInt())
	{
		strdoc += strindent;
		strdoc += "<integer>";
		char temp[32] = {0};
		sprintf(temp, "%" PRId64, pval.asInt64());
		strdoc += temp;
		strdoc += "</integer>\n";
	}
	else if (pval.isFloat())
	{
		strdoc += strindent;
		strdoc += "<real>";

		double v = pval.asFloat();
		if (numeric_limits<double>::infinity() == v)
		{
			strdoc += "+infinity";
		}
		else
		{
			char temp[32] = {0};
			if (floor(v) == v)
			{
				sprintf(temp, "%" PRId64, (int64_t)v);
			}
			else
			{
				sprintf(temp, "%.15lf", v);
			}
			strdoc += temp;
		}

		strdoc += "</real>\n";
	}
}

void PWriter::XMLEscape(string &strval)
{
	StringReplace(strval, "&", "&amp;");
	StringReplace(strval, "<", "&lt;");
	//StringReplace(strval, ">", "&gt;");		//option
	//StringReplace(strval, "'", "&apos;");		//option
	//StringReplace(strval, "\"", "&quot;");	//option
}

string &PWriter::StringReplace(string &context, const string &from, const string &to)
{
	size_t lookHere = 0;
	size_t foundHere;
	while ((foundHere = context.find(from, lookHere)) != string::npos)
	{
		context.replace(foundHere, from.size(), to);
		lookHere = foundHere + to.size();
	}
	return context;
}
